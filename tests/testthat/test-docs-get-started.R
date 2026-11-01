# test-docs-get-started.R: DS-2 US-1 get-started vignette laws (docs/site v2).
# Three claims this file holds shut, each with constructed-broken controls that
# fire it and a constructed-perfect control that greens it (dead-metric law):
#  (1) claims-are-measured: every digit-bearing token in the vignette PROSE
#      (outside fenced code blocks) must byte-exist as an identical whole
#      token in a committed witness corpus (DESCRIPTION, R/, inst/CITATION, the
#      committed renv lockfile). An unwitnessed number in prose is a violation.
#      Token extraction is a pure char walk (no regex engine -- this base's
#      tre quirks; the .ds2_cell_split precedent).
#  (2) the five-minute path exists, really calls the end-to-end faces
#      (ms_variants -> ms_tally -> ms_signature -> ms_refdb) and names the
#      committed specimen fixture it executes against.
#  (3) registration: the vignette is named in the _pkgdown.yml articles block
#      and the navbar carries an internal href into the built articles tree.

# --- helpers -------------------------------------------------------------------

.gs_which_eq <- function(vec, s) {
  out <- integer(0)
  for (i in seq_along(vec)) if (identical(vec[i], s)) out <- c(out, i)
  out
}

.gs_IS_TOKEN <- c(LETTERS, letters, 0:9, ".", "_", "-")

# maximal runs of token chars that contain at least one digit; trailing
# sentence dots are stripped so "1.71." rides as "1.71"
.gs_tokens <- function(lines) {
  hits <- character(0)
  for (l in lines) {
    ch <- strsplit(l, "")[[1L]]
    run <- character(0)
    flush <- function() {
      if (length(run) && any(run %in% 0:9)) {
        s <- paste0(run, collapse = "")
        while (nzchar(s) && endsWith(s, ".")) {
          s <- substr(s, 1L, nchar(s) - 1L)
        }
        if (nzchar(s)) hits <<- c(hits, s)
      }
      run <<- character(0)
    }
    for (c0 in ch) {
      if (c0 %in% .gs_IS_TOKEN) run <- c(run, c0) else flush()
    }
    flush()
  }
  unique(hits)
}

# split the Rmd bytes into header / prose / code. Prose excludes the YAML
# header and everything inside ``` fences (delimiters carry no claims).
.gs_split <- function(lines) {
  header <- character(0); prose <- character(0); code <- character(0)
  stage <- "header"
  open <- FALSE
  for (l in lines) {
    if (identical(stage, "header")) {
      header <- c(header, l)
      if (identical(l, "---") && length(header) > 1L) stage <- "body"
      next
    }
    if (startsWith(l, "```")) { open <- !open; next }
    if (open) code <- c(code, l) else prose <- c(prose, l)
  }
  list(header = header, prose = prose, code = code)
}

.gs_witness_tokens <- function(root) {
  corpus <- character(0)
  add <- function(f) {
    if (file.exists(f)) corpus <<- c(corpus, readLines(f, warn = FALSE))
  }
  add(file.path(root, "DESCRIPTION"))
  add(file.path(root, "inst", "CITATION"))
  add(file.path(root, "docs", "paper", "renv.lock"))
  for (f in list.files(file.path(root, "R"), pattern = "[.]R$",
                       full.names = TRUE)) {
    corpus <- c(corpus, readLines(f, warn = FALSE))
  }
  .gs_tokens(corpus)
}

# --- laws ------------------------------------------------------------------------

.gs_law_prose <- function(lines, root) {
  parts <- .gs_split(lines)
  toks <- .gs_tokens(parts$prose)
  wit <- .gs_witness_tokens(root)
  unwit <- character(0)
  for (t in toks) if (!t %in% wit) unwit <- c(unwit, t)
  v <- character(0)
  if (length(unwit)) {
    v <- c(v, paste0("unwitnessed numerics in prose: ",
                     paste0(unwit, collapse = ", ")))
  }
  list(violations = v, tokens = length(toks))
}

.gs_law_path <- function(lines) {
  v <- character(0)
  parts <- .gs_split(lines)
  code <- paste0(parts$code, collapse = "\n")
  for (face in c("ms_variants", "ms_tally", "ms_signature", "ms_refdb")) {
    if (!grepl(face, code, fixed = TRUE)) {
      v <- c(v, paste0("five-minute path never calls ", face, "()"))
    }
  }
  prose <- paste0(parts$prose, collapse = "\n")
  for (h in c("Install", "Five-minute", "Anatomy")) {
    if (!grepl(h, prose, fixed = TRUE)) {
      v <- c(v, paste0("missing prose section marker: ", h))
    }
  }
  list(violations = v)
}

.gs_law_fixture <- function(lines, root) {
  v <- character(0)
  all_txt <- paste0(lines, collapse = "\n")
  if (!grepl("fixtures/sigprofiler_sbs96_specimen.txt", all_txt, fixed = TRUE)) {
    v <- c(v, "vignette never names the committed specimen fixture")
  }
  if (!file.exists(file.path(root, "tests", "testthat", "fixtures",
                             "sigprofiler_sbs96_specimen.txt"))) {
    v <- c(v, "named specimen fixture does not exist on disk")
  }
  list(violations = v)
}

.gs_law_registration <- function(yml) {
  v <- character(0)
  a <- .gs_which_eq(yml, "articles:")
  if (length(a) != 1L) {
    return(list(violations = paste0("articles: block hits=", length(a),
                                    " (exactly 1 required)")))
  }
  art_items <- character(0)
  in_contents <- FALSE
  for (i in (a[1L] + 1L):length(yml)) {
    l <- yml[i]
    if (!nzchar(trimws(l))) next
    if (!startsWith(l, " ") && !startsWith(l, "-")) break
    t <- trimws(l)
    if (identical(t, "contents:")) { in_contents <- TRUE; next }
    if (startsWith(l, "- title:")) { in_contents <- FALSE; next }
    if (in_contents && startsWith(t, "- ")) {
      art_items <- c(art_items, trimws(sub("^- ", "", t)))
    }
  }
  if (!("get-started" %in% art_items)) {
    v <- c(v, "get-started is not registered in articles contents")
  }
  if (!any(grepl("articles/get-started.html", yml, fixed = TRUE))) {
    v <- c(v, "no navbar href articles/get-started.html in _pkgdown.yml")
  }
  list(violations = v)
}

# --- repository gate -----------------------------------------------------------------

.gs_shipped <- function() {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  vf <- file.path(.ms_root, "vignettes", "get-started.Rmd")
  yf <- file.path(.ms_root, "_pkgdown.yml")
  if (!file.exists(vf)) {
    stop("vignettes/get-started.Rmd missing from the checkout (US-1 defect)")
  }
  list(lines = readLines(vf, warn = FALSE), yml = readLines(yf, warn = FALSE))
}

# --- green halves ---------------------------------------------------------------------

test_that("US-1 every prose numeral of get-started is byte-witnessed", {
  d <- .gs_shipped()
  r <- .gs_law_prose(d$lines, .ms_root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_gte(r$tokens, 1L)   # vacuous-green ban: the token census must see life
  cat("US-1 PROSE CENSUS: digit-tokens=", r$tokens, " unwitnessed=0\n", sep = "")
})

test_that("US-1 the five-minute path runs the four faces and names its fixture", {
  d <- .gs_shipped()
  v <- c(.gs_law_path(d$lines)$violations,
         .gs_law_fixture(d$lines, .ms_root)$violations)
  expect_identical(v, character(0), info = paste0(v, collapse = "\n"))
})

test_that("US-1 get-started is registered in articles and the navbar", {
  d <- .gs_shipped()
  r <- .gs_law_registration(d$yml)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
})

# --- red halves: constructed-broken controls, every rule must fire ---------------------

test_that("US-1 an unwitnessed numeral injected into prose reddens the law", {
  d <- .gs_shipped()
  k <- .gs_which_eq(d$lines, "## Install")
  expect_length(k, 1L)
  tampered <- append(d$lines, "The kernel ships 999999 parallel lanes.",
                     after = k[1L])
  r <- .gs_law_prose(tampered, .ms_root)
  expect_true(any(grepl("999999", r$violations, fixed = TRUE)))
})

test_that("US-1 a tampered dependency floor reddens the witness law", {
  d <- .gs_shipped()
  k <- .gs_which_eq(d$lines, "## Install")
  expect_length(k, 1L)
  tampered <- append(d$lines, "The R floor is 4.2 and the toolchain floor is 99.99.",
                     after = k[1L])
  r <- .gs_law_prose(tampered, .ms_root)
  expect_true(any(grepl("unwitnessed numerics", r$violations, fixed = TRUE)))
})

test_that("US-1 defacing the ms_refdb assignment names the path gap", {
  d <- .gs_shipped()
  tampered <- vapply(d$lines, function(l) {
    if (grepl("ms_refdb", l, fixed = TRUE) && grepl("<-", l, fixed = TRUE)) {
      "# defaced by the control"
    } else {
      l
    }
  }, character(1))
  r <- .gs_law_path(tampered)
  expect_true(any(grepl("never calls ms_refdb()", r$violations, fixed = TRUE)))
})

test_that("US-1 a phantom fixture reference is named", {
  d <- .gs_shipped()
  tampered <- vapply(d$lines, function(l) {
    gsub("sigprofiler_sbs96_specimen.txt", "ghost_fixture_matrix.txt", l,
         fixed = TRUE)
  }, character(1))
  r <- .gs_law_fixture(tampered, .ms_root)
  expect_true(any(grepl("never names the committed specimen fixture",
                        r$violations, fixed = TRUE)))
})

test_that("US-1 dropping the navbar registration is named", {
  d <- .gs_shipped()
  keep <- vapply(d$yml, function(l) {
    !grepl("articles/get-started.html", l, fixed = TRUE)
  }, logical(1))
  r <- .gs_law_registration(d$yml[keep])
  expect_true(any(grepl("navbar href", r$violations, fixed = TRUE)))
})

test_that("US-1 dropping the articles entry is named", {
  d <- .gs_shipped()
  keep <- vapply(d$yml, function(l) !identical(trimws(l), "- get-started"),
                 logical(1))
  r <- .gs_law_registration(d$yml[keep])
  expect_true(any(grepl("not registered in articles", r$violations,
                        fixed = TRUE)))
})

test_that("US-1 the constructed-perfect skeleton greens the laws (live control)", {
  skeleton <- c(
    "---", "title: control", "---",
    "## Install",
    "The R floor is 4.3 and the toolchain floor is 1.71.",
    "## Five-minute path",
    "```{r}",
    "# fixture: fixtures/sigprofiler_sbs96_specimen.txt",
    "v <- ms_variants(tab)",
    "cat1 <- ms_tally(v, genome)",
    "sig <- ms_signature(sigs, exps, summary)",
    "db <- ms_refdb_bundled()",
    "```",
    "The specimen rides the committed fixture named above.",
    "## Anatomy of the output")
  r1 <- .gs_law_prose(skeleton, .ms_root)
  r2 <- .gs_law_path(skeleton)
  r3 <- .gs_law_fixture(skeleton, .ms_root)
  expect_identical(c(r1$violations, r2$violations, r3$violations),
                    character(0))
  expect_identical(r1$tokens, 2L)   # 4.3 and 1.71 -- both byte-witnessed
})
