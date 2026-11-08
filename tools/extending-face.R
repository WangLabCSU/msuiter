#!/usr/bin/env Rscript
# extending-face.R: DS-4 US-H3 instrument (docs/site v4). Two surfaces, both
# re-derivation-only, no hand-typed truth:
#   (1) API surface -- every backtick `fn()` / \code{fn}-shaped token the API
#       page presents must resolve against the NAMESPACE face (exports), the
#       live namespace (msuiter::: internals), the sanctioned-external
#       registry, a page-self-definition, or the reasoned allowlist.
#   (2) Cross-page navigation -- internal links of the legacy pages must
#       resolve against the built-article name set (vignette basenames +
#       pkgdown registrations) and anchors against recomputed heading slugs.
# CLI face (--check) speaks the census and exits nonzero on any violation;
# the MSUITER_TOOL_NO_MAIN marker separates sourcing from invocation.

.ef_args <- commandArgs(FALSE)
.ef_args <- as.character(.ef_args[nzchar(as.character(.ef_args))])
.ef_args <- .ef_args[!grepl("^--file=", .ef_args)]

.ef_get <- function(pref, required = TRUE) {
  hit <- grepl(paste0("^", pref), .ef_args)
  if (!any(hit)) {
    if (required) .ef_stop(paste0("missing required argument ", pref, "<value>"))
    return("")
  }
  sub(paste0("^", pref), "", .ef_args[which(hit)[1L]])
}

.ef_flag <- function(name) any(grepl(paste0("^", name), .ef_args))

.ef_stop <- function(msg) stop(msg, domain = NA, call. = FALSE)

.ef_root <- function() {
  r <- .ef_get("--root=", required = FALSE)
  if (nzchar(r)) return(normalizePath(r))
  p <- normalizePath(getwd())
  repeat {
    if (file.exists(file.path(p, "DESCRIPTION"))) return(p)
    up <- dirname(p)
    if (identical(up, p)) .ef_stop("no package root above the working directory")
    p <- up
  }
}

.ef_trim <- function(x) gsub("^[[:space:]]+|[[:space:]]+$", "", x)

# sanctioned registries: every entry must speak a reason (the law re-checks
# nzchar and absence-of-rot); observation-only membership, never a wildcard
ef_allowlist <- function() {
  c(fit_fn = "user-supplied implementation placeholder the page presents as the registry callback contract",
    format = "base R face named as an example S7 method the reader may add",
    stop = "base R face the page names only to forbid it as an error channel",
    c = "base R constructor appearing inside the error payload shape example")
}

ef_externals <- function() {
  c("S7::new_class" = "S7 is the declared class system (DESCRIPTION Imports); the page presents its constructor face",
    "S7::methods_register" = "S7 registration face the page discusses as a load-order caveat, not as msuiter API",
    "rlang::abort" = "rlang is the declared condition-signal dependency (DESCRIPTION Imports) the error protocol routes through")
}

# --- namespace face ------------------------------------------------------------------------

ef_namespace_exports <- function(ns_path) {
  if (!file.exists(ns_path)) .ef_stop(paste0("NAMESPACE face not readable: ", ns_path))
  ln <- readLines(ns_path, warn = FALSE)
  vals <- character(0)
  for (l in ln) {
    s <- .ef_trim(l)
    if (startsWith(s, "export(") && endsWith(s, ")")) {
      vals <- c(vals, substr(s, 8L, nchar(s) - 1L))
    }
  }
  if (!length(vals)) .ef_stop(paste0("vacuous: NAMESPACE face at ", ns_path,
                                     " carries zero exports"))
  vals
}

# --- built-article name set ------------------------------------------------------------------

# vignette basenames union the pkgdown registrations: an article name is
# built only if it appears in either face (the coherence law owns the
# bijection; this face consumes it)
ef_article_set <- function(root, minus_articles = character(0)) {
  vd <- file.path(root, "vignettes")
  if (!dir.exists(vd)) .ef_stop(paste0("vacuous: no vignettes directory at ", vd))
  vb <- sub("[.]Rmd$", "", list.files(vd, pattern = "[.]Rmd$"))
  py <- file.path(root, "_pkgdown.yml")
  if (!file.exists(py)) .ef_stop(paste0("_pkgdown.yml missing at ", py))
  pl <- readLines(py, warn = FALSE)
  ai <- which(.ef_trim(pl) == "articles:")
  if (!length(ai)) .ef_stop("vacuous: _pkgdown.yml declares no articles: roster")
  body <- character(0)
  for (l in pl[(ai[1L] + 1L):length(pl)]) {
    s <- .ef_trim(l)
    # the roster ends at the next top-level key: a col-0 non-blank line that
    # is not a list item (pkgdown renders list dashes at column zero)
    if (nzchar(s) && !grepl("^[[:space:]]", l) && !startsWith(s, "-")) break
    body <- c(body, l)
  }
  registered <- character(0)
  for (l in body) {
    s <- .ef_trim(l)
    if (startsWith(s, "- ") && !grepl("title:", s, fixed = TRUE) &&
        !grepl("contents:", s, fixed = TRUE)) {
      tok <- .ef_trim(sub("^-", "", s))
      # pkgdown registers a subdirectory article under its articles/ prefix
      # (pkg$vignettes$name), so the roster spells them that way; the link law
      # keys on the stem the built page actually lives under. Campaign filenames
      # carry uppercase lane ids and dots (G0, M0-01, v0.1), so the shape rule
      # admits both; the coherence law owns the ghost check.
      tok <- sub("^articles/", "", tok)
      if (grepl("^[A-Za-z0-9][-A-Za-z0-9._]*$", tok)) {
        registered <- c(registered, tok)
      }
    }
  }
  if (!length(registered)) {
    .ef_stop("vacuous: _pkgdown.yml articles roster carries zero names")
  }
  setdiff(sort(unique(c(vb, registered))), minus_articles)
}

# pandoc-flavoured heading slug (the law recomputes slugs from the page's
# own headings; the author's href must match the re-derivation)
ef_slug <- function(heading) {
  s <- .ef_trim(heading)
  s <- gsub("^#+[[:space:]]*", "", s)
  s <- gsub("[*_`]", "", s)
  s <- gsub("[^a-zA-Z0-9_ -]", "", s)
  s <- tolower(s)
  gsub("[[:space:]]", "-", s)
}

# --- prose/token face ----------------------------------------------------------------------

# fence-pair prose mask: TRUE on lines outside any fenced block
.ef_prose_mask <- function(lines, at) {
  prose <- rep(TRUE, length(lines))
  fence <- which(grepl("^```", lines))
  k <- 1L
  while (k <= length(fence)) {
    a <- fence[k]
    b <- if (k + 1L <= length(fence)) fence[k + 1L] else length(lines)
    prose[a:b] <- FALSE
    k <- k + 2L
  }
  if (!sum(prose)) .ef_stop(paste0("vacuous: zero prose lines in ", at))
  prose
}

# backtick-delimited spans of a line
.ef_backtick_spans <- function(line) {
  ch <- strsplit(line, "")[[1L]]
  out <- character(0); cur <- character(0); inb <- FALSE
  for (c0 in ch) {
    if (identical(c0, "`")) {
      if (inb) out <- c(out, paste0(cur, collapse = ""))
      cur <- character(0); inb <- !inb
    } else if (inb) {
      cur <- c(cur, c0)
    }
  }
  out
}

# \code{...} spans of a line (brace-balanced walk)
.ef_code_spans <- function(line) {
  ch <- strsplit(line, "")[[1L]]
  needle <- strsplit("\\code{", "")[[1L]]
  m <- length(needle); n <- length(ch)
  out <- character(0)
  if (n < m) return(out)
  i <- 1L
  while (i <= n - m + 1L) {
    if (all(ch[i + seq_len(m) - 1L] == needle)) {
      depth <- 1L; j <- i + m; cur <- character(0)
      while (j <= n && depth > 0L) {
        if (identical(ch[[j]], "{")) depth <- depth + 1L
        if (identical(ch[[j]], "}")) depth <- depth - 1L
        if (depth > 0L) cur <- c(cur, ch[[j]])
        j <- j + 1L
      }
      out <- c(out, paste0(cur, collapse = ""))
      i <- j
    } else i <- i + 1L
  }
  out
}

# identifier immediately followed by "(" inside a span
.ef_span_tokens <- function(span) {
  ch <- strsplit(span, "")[[1L]]
  ident <- c(letters, LETTERS, as.character(0:9), ".", "_", ":")
  out <- character(0)
  n <- length(ch); i <- 1L
  while (i <= n) {
    if (ch[[i]] %in% ident) {
      j <- i
      while (j <= n && ch[[j]] %in% ident) j <- j + 1L
      if (j <= n && identical(ch[[j]], "(")) {
        out <- c(out, paste0(ch[i:(j - 1L)], collapse = ""))
      }
      i <- j
    } else i <- i + 1L
  }
  out
}

.ef_page_tokens <- function(lines, prose) {
  toks <- character(0)
  for (i in seq_along(lines)) {
    if (!prose[i]) next
    spans <- c(.ef_backtick_spans(lines[i]), .ef_code_spans(lines[i]))
    for (sp in spans) toks <- c(toks, .ef_span_tokens(sp))
  }
  unique(toks)
}

# a token the page's own code defines: `tok <- ...` at any line
.ef_defined_on_page <- function(tok, lines) {
  key <- paste0("^[[:space:]]*", gsub(".", "[.]", tok, fixed = TRUE),
                 "[[:space:]]*<[-]")
  any(grepl(key, lines))
}

# --- link face ------------------------------------------------------------------------------

# markdown link targets of a line: [text](target); images and externals dropped
.ef_links <- function(lines, prose) {
  out_line <- integer(0); out_tgt <- character(0)
  for (i in seq_along(lines)) {
    if (!prose[i]) next
    ch <- strsplit(lines[i], "")[[1L]]
    n <- length(ch); j <- 1L
    while (j <= n) {
      if (identical(ch[[j]], "[") && !(j > 1L && identical(ch[[j - 1L]], "!"))) {
        k <- j + 1L
        while (k <= n && !identical(ch[[k]], "]")) k <- k + 1L
        if (k <= n && k + 1L <= n && identical(ch[[k + 1L]], "(")) {
          p <- k + 2L; cur <- character(0)
          while (p <= n && !identical(ch[[p]], ")")) {
            cur <- c(cur, ch[[p]]); p <- p + 1L
          }
          if (p <= n) {
            tg <- paste0(cur, collapse = "")
            if (!grepl("^[a-z][a-z0-9+.-]*://", tg) &&
                !grepl("^mailto:", tg, fixed = TRUE)) {
              out_line <- c(out_line, i); out_tgt <- c(out_tgt, tg)
            }
            j <- p
          }
        }
        if (k <= n) j <- k else j <- j + 1L
      } else j <- j + 1L
    }
  }
  data.frame(line = out_line, target = out_tgt, stringsAsFactors = FALSE)
}

# --- the audit ---------------------------------------------------------------------------------

# pages: character vector; the LAST page is the API page (token law); link
# navigation is audited across every page given. ns_env: the live namespace
# for msuiter::: internals; loaded on demand, fail-closed.
ef_audit <- function(pages, ns_path, root, minus_articles = character(0),
                     ns_env = NULL) {
  for (p in pages) if (!file.exists(p)) .ef_stop(paste0("page not readable: ", p))
  exports <- ef_namespace_exports(ns_path)
  articles <- ef_article_set(root, minus_articles)
  if (!nzchar(root) || !dir.exists(root)) .ef_stop("package root unreadable")
  allow <- ef_allowlist(); extn <- ef_externals()
  if (is.null(ns_env)) {
    if (!requireNamespace("msuiter", quietly = TRUE)) {
      .ef_stop("msuiter namespace unavailable: internal faces are checked live (tool face fail-closed)")
    }
    ns_env <- asNamespace("msuiter")
  }
  v <- character(0)
  n_tokens <- 0L; n_exported <- 0L; n_internal <- 0L; n_external <- 0L
  n_selfdef <- 0L; n_allowlisted <- 0L
  allowlisted_seen <- character(0); external_seen <- character(0)
  n_links <- 0L; n_links_ok <- 0L; n_anchors <- 0L
  per_page <- list()

  api <- pages[length(pages)]
  alines <- readLines(api, warn = FALSE)
  aprose <- .ef_prose_mask(alines, api)
  toks <- .ef_page_tokens(alines, aprose)
  n_tokens <- length(toks)
  if (n_tokens < 8L) {
    .ef_stop(paste0("vacuous: the API page ", basename(api),
                    " presents only ", n_tokens, " fn()-shaped tokens"))
  }
  for (tok in toks) {
    if (grepl("::", tok, fixed = TRUE)) {
      pkg <- gsub("[:].*$", "", tok)
      nm <- gsub("^[^:]+[:]+", "", tok)
      if (identical(pkg, "msuiter")) {
        if (nzchar(nm) && exists(nm, envir = ns_env, inherits = FALSE)) {
          n_internal <- n_internal + 1L
        } else {
          v <- c(v, paste0("internal face off the namespace: msuiter:::", nm))
        }
      } else {
        if (tok %in% names(extn)) {
          if (!nzchar(extn[[tok]])) {
            v <- c(v, paste0("sanctioned-external without a reason: ", tok))
          } else external_seen <- c(external_seen, tok)
          n_external <- n_external + 1L
        } else {
          v <- c(v, paste0("qualified token off the sanctioned-external registry: ",
                          tok))
        }
      }
    } else if (tok %in% exports) {
      n_exported <- n_exported + 1L
    } else if (.ef_defined_on_page(tok, alines)) {
      n_selfdef <- n_selfdef + 1L
    } else if (tok %in% names(allow)) {
      if (!nzchar(allow[[tok]])) {
        v <- c(v, paste0("allowlisted token without a reason: ", tok))
      } else allowlisted_seen <- c(allowlisted_seen, tok)
      n_allowlisted <- n_allowlisted + 1L
    } else {
      v <- c(v, paste0("token presents package API but is off the namespace: ", tok))
    }
  }

  for (i in seq_along(pages)) {
    lines <- readLines(pages[i], warn = FALSE)
    prose <- .ef_prose_mask(lines, pages[i])
    headings <- lines[grepl("^#{1,6}[[:space:]]", lines)]
    slugs <- vapply(headings, ef_slug, character(1), USE.NAMES = FALSE)
    lk <- .ef_links(lines, prose)
    ok_here <- 0L
    for (r in seq_len(nrow(lk))) {
      tg <- lk$target[r]
      ln <- lk$line[r]
      n_links <- n_links + 1L
      resolved <- FALSE
      if (startsWith(tg, "#")) {
        n_anchors <- n_anchors + 1L
        if (identical(tg, "#")) {
          v <- c(v, paste0("bare anchor href on ", basename(pages[i]),
                           " at line ", ln))
        } else if (sub("^#", "", tg) %in% slugs) {
          ok_here <- ok_here + 1L; resolved <- TRUE
        } else {
          v <- c(v, paste0("anchor off the recomputed heading slugs: ", tg,
                           " (", basename(pages[i]), " line ", ln, ")"))
        }
      } else if (grepl("[.]html$", tg)) {
        nm <- sub("[.]html$", "", tg)
        if (startsWith(nm, "articles/")) {
          # pkgdown builds every vignette and article into the one articles/
          # directory, so a source page's sibling href must be bare. An
          # articles/-prefixed href resolves to /articles/articles/<nm>.html.
          v <- c(v, paste0("articles-prefixed sibling href resolves one ",
                          "directory too deep in the built site: ", tg, " (",
                          basename(pages[i]), " line ", ln, ")"))
        } else if (grepl("/", nm, fixed = TRUE)) {
          v <- c(v, paste0("site-area link the article set cannot adjudicate: ",
                          tg, " (", basename(pages[i]), " line ", ln, ")"))
        } else if (nm %in% articles) {
          ok_here <- ok_here + 1L; resolved <- TRUE
        } else {
          v <- c(v, paste0("link names an unbuilt article: ", tg, " (",
                          basename(pages[i]), " line ", ln, ")"))
        }
      } else if (startsWith(tg, "../") || grepl("^/", tg)) {
        resolved <- TRUE # site-area target outside this law's reach
      } else {
        v <- c(v, paste0("internal link shape the law does not recognise: ",
                        tg, " (", basename(pages[i]), " line ", ln, ")"))
      }
      if (resolved) n_links_ok <- n_links_ok + 1L
    }
    per_page[[length(per_page) + 1L]] <- list(links = nrow(lk))
  }
  if (!n_links) {
    .ef_stop("vacuous: zero internal links across the audited pages")
  }
  for (i in seq_along(pages)) {
    if (per_page[[i]]$links < 1L) {
      v <- c(v, paste0("legacy page carries no internal navigation: ",
                      basename(pages[i])))
    }
  }
  list(violations = v, pages = pages,
       n_tokens = n_tokens, n_exported = n_exported, n_internal = n_internal,
       n_external = n_external, n_selfdef = n_selfdef,
       n_allowlisted = n_allowlisted,
       allowlisted_seen = unique(allowlisted_seen),
       external_seen = unique(external_seen),
       n_links = n_links, n_links_ok = n_links_ok, n_anchors = n_anchors,
       per_page = per_page)
}

# --- CLI face ----------------------------------------------------------------------------------

if (!identical(Sys.getenv("MSUITER_TOOL_NO_MAIN", ""), "1")) {
  root <- .ef_root()
  if (!.ef_flag("--check")) {
    cat("usage: extending-face.R --root=<path> [--page=<api page>] [--check]\n")
    quit(status = 2L)
  }
  page <- .ef_get("--page=", required = FALSE)
  legacy <- file.path(root, "vignettes",
                      c("tour.Rmd", "scenarios.Rmd", "extending.Rmd"))
  for (lg in legacy) {
    if (!file.exists(lg)) .ef_stop(paste0("legacy page missing: ", lg))
  }
  pages <- if (nzchar(page)) c(legacy[1L:2L], page) else legacy
  a <- ef_audit(pages, file.path(root, "NAMESPACE"), root)
  cat(paste0("EF CENSUS: api-page=", basename(pages[length(pages)]),
             " tokens=", a$n_tokens, " exported=", a$n_exported,
             " internal=", a$n_internal, " external=", a$n_external,
             " selfdef=", a$n_selfdef, " allowlisted=", a$n_allowlisted,
             " links=", a$n_links, " ok=", a$n_links_ok,
             " anchors=", a$n_anchors,
             " violations=", length(a$violations), "\n", sep = ""))
  for (v0 in a$violations) cat("VIOLATION: ", v0, "\n", sep = "")
  quit(status = if (length(a$violations)) 1L else 0L)
}
