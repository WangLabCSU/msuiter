# scenarios-gallery.R -- DS-3 US-G1 witness gallery tool (docs/site v3).
# Derives the committed scenario-witness roster from the bytes on disk
# (no hand roster), stamps each file with an in-process sha256
# (digest::digest(file = TRUE) -- never an external shasum), counts rows and
# header columns, and renders one HTML card per witness: provenance stamp,
# row/column census and a verbatim excerpt of the leading data rows. The
# vignette sources this file with MSUITER_TOOL_NO_MAIN=1 set and prints
# scg_render(); the CLI writes manifest.tsv plus a standalone gallery page.
# No hand-typed numerics ride the page: every digit is re-derived here.
# usage: Rscript tools/scenarios-gallery.R --out=<dir> [--root=<dir>]

scg_EXCERPT_ROWS <- 5L

.args <- commandArgs(FALSE)
.args <- as.character(.args[nzchar(as.character(.args))])
.scg_get <- function(pref, required = TRUE) {
  hit <- grepl(paste0("^", pref), .args)
  if (!any(hit)) {
    if (required) stop("missing required argument ", pref, "<value>",
                       domain = NA)
    return("")
  }
  sub(pref, "", .args[which(hit)[1L]])
}

.scg_stop <- function(msg) stop(msg, domain = NA, call. = FALSE)

scg_root <- function() {
  root <- .scg_get("--root=", required = FALSE)
  if (nzchar(root)) return(normalizePath(root))
  p <- normalizePath(getwd())
  repeat {
    if (file.exists(file.path(p, "DESCRIPTION"))) return(p)
    up <- dirname(p)
    if (identical(up, p)) {
      .scg_stop("vacuous: no package root above the working directory")
    }
    p <- up
  }
}

scg_witness_dir <- function(root) file.path(root, "bench", "scenarios", "out")

scg_roster <- function(root) {
  wdir <- scg_witness_dir(root)
  if (!dir.exists(wdir)) {
    .scg_stop(paste0("vacuous: no witness directory at ", wdir))
  }
  files <- sort(list.files(wdir))
  if (!length(files)) {
    .scg_stop(paste0("vacuous: zero witness files under ", wdir))
  }
  files
}

scg_sha <- function(f) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    .scg_stop("digest namespace unavailable: witness hashing is in-process by law")
  }
  h <- digest::digest(f, algo = "sha256", file = TRUE)
  if (length(h) != 1L || nchar(h) != 64L ||
      !all(strsplit(h, "")[[1L]] %in% strsplit("0123456789abcdef", "")[[1L]])) {
    .scg_stop(paste0("digest desync: malformed sha256 for ", f))
  }
  h
}

# quote-aware single-delimiter cell walk (no regex engine: this base's
# tre quirks; the DS-2 .br_links/.cg_find_all precedent)
scg_cells <- function(line, delim) {
  ch <- strsplit(line, "")[[1L]]
  n <- length(ch)
  out <- character(0)
  cur <- character(0)
  quoted <- FALSE
  i <- 1L
  while (i <= n) {
    c0 <- ch[[i]]
    if (identical(c0, "\"")) {
      if (quoted && i < n && identical(ch[[i + 1L]], "\"")) {
        cur <- c(cur, "\"")
        i <- i + 2L
        next
      }
      quoted <- !quoted
    } else if (!quoted && identical(c0, delim)) {
      out <- c(out, paste0(cur, collapse = ""))
      cur <- character(0)
    } else {
      cur <- c(cur, c0)
    }
    i <- i + 1L
  }
  c(out, paste0(cur, collapse = ""))
}

scg_delim <- function(rel) {
  if (endsWith(rel, ".tsv")) "\t" else ","
}

scg_escape <- function(s) {
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s
}

# rel / sha256 / rows / cols -- rows and cols travel as CHARACTER tokens so
# no numeric formatting pass can ever re-mint a digit between disk and page.
scg_derive <- function(root) {
  wdir <- scg_witness_dir(root)
  files <- scg_roster(root)
  sha <- vapply(files, function(f) scg_sha(file.path(wdir, f)), character(1),
                USE.NAMES = FALSE)
  lines <- lapply(files, function(f) readLines(file.path(wdir, f), warn = FALSE))
  rows <- vapply(lines, function(l) as.character(length(l)), character(1),
                 USE.NAMES = FALSE)
  cols <- character(length(files))
  for (i in seq_along(files)) {
    hd <- if (length(lines[[i]])) lines[[i]][1L] else ""
    cols[i] <- as.character(length(scg_cells(hd, scg_delim(files[i]))))
  }
  data.frame(rel = files, sha256 = sha, rows = rows, cols = cols,
             stringsAsFactors = FALSE)
}

scg_cards <- function(der, root) {
  wdir <- scg_witness_dir(root)
  out <- character(0)
  for (i in seq_along(der$rel)) {
    rel <- der$rel[i]
    lines <- readLines(file.path(wdir, rel), warn = FALSE)
    cells <- lapply(lines, function(l) scg_cells(l, scg_delim(rel)))
    out <- c(out,
             paste0("<div class=\"witness-card\" data-witness=\"", rel, "\">"),
             paste0("<h3>", scg_escape(rel), "</h3>"),
             paste0("<p>sha256 <code class=\"witness-sha\">", der$sha256[i],
                    "</code></p>"),
             paste0("<p>rows=", der$rows[i], " cols=", der$cols[i], "</p>"))
    out <- c(out, "<table class=\"witness-excerpt\">")
    for (r in seq_len(min(1L + scg_EXCERPT_ROWS, length(lines)))) {
      tag <- if (r == 1L) "th" else "td"
      out <- c(out, paste0("<tr>",
                           paste0(vapply(cells[[r]], function(c0) {
                             paste0("<", tag, ">", scg_escape(c0), "</", tag, ">")
                           }, character(1), USE.NAMES = FALSE), collapse = ""),
                           "</tr>"))
    }
    out <- c(out, "</table>", "</div>")
  }
  out
}

scg_render <- function(root) {
  der <- scg_derive(root)
  header <- c(
    "<div class=\"gallery-census\">",
    paste0("<p>witnesses=", nrow(der),
           " rows-total=", sum(as.integer(der$rows)),
           " columns-total=", sum(as.integer(der$cols)), "</p>"),
    "</div>")
  c(header, scg_cards(der, root))
}

# --- US-H2 prose-census face ---------------------------------------------------------------

# The one census face for scenario prose: every multi-digit numeral the page
# states about the atlas must be derivable from the committed witness bytes
# themselves (digit runs plus header/row/column structural counts), or be
# covered by an ms-num marker whose kind/reason contract this face re-checks.

.scg_DIGITS <- strsplit("0123456789", "")[[1L]]

.scg_digit_runs <- function(s) {
  ch <- strsplit(s, "")[[1L]]
  out <- character(0); cur <- character(0)
  for (c0 in ch) {
    if (c0 %in% .scg_DIGITS) {
      cur <- c(cur, c0)
    } else {
      if (length(cur) >= 2L) out <- c(out, paste0(cur, collapse = ""))
      cur <- character(0)
    }
  }
  if (length(cur) >= 2L) out <- c(out, paste0(cur, collapse = ""))
  out
}

# attribute extraction by char walk (no capture regex: this base's tre law)
.scg_attr <- function(line, key) {
  ch <- strsplit(line, "")[[1L]]
  nd <- strsplit(paste0(key, "=\""), "")[[1L]]
  m <- length(nd)
  if (length(ch) < m) return(NA_character_)
  for (i in seq_len(length(ch) - m + 1L)) {
    if (all(ch[i + seq_len(m) - 1L] == nd)) {
      j <- i + m; cur <- character(0)
      while (j <= length(ch) && !identical(ch[[j]], "\"")) {
        cur <- c(cur, ch[[j]]); j <- j + 1L
      }
      return(paste0(cur, collapse = ""))
    }
  }
  NA_character_
}

scg_numset <- function(dir) {
  if (!dir.exists(dir)) .scg_stop(paste0("vacuous: no witness directory at ", dir))
  files <- sort(list.files(dir, pattern = "[.]csv$"))
  if (!length(files)) .scg_stop(paste0("vacuous: zero csv witnesses under ", dir))
  vals <- character(0)
  for (f in files) {
    ln <- readLines(file.path(dir, f), warn = FALSE)
    if (!length(ln)) next
    vals <- c(vals, as.character(length(ln)), as.character(length(ln) - 1L))
    hdr <- scg_cells(ln[[1L]], scg_delim(f))
    vals <- c(vals, as.character(length(hdr)), as.character(max(length(hdr) - 1L, 0L)))
    for (l in ln) vals <- c(vals, .scg_digit_runs(l))
  }
  sort(unique(vals[grepl("^[0-9][0-9]+$", vals)]))
}

scg_prose_audit <- function(page, numset) {
  if (!file.exists(page)) .scg_stop(paste0("scenario page not readable: ", page))
  if (!length(numset)) .scg_stop("vacuous: empty witness census")
  lines <- readLines(page, warn = FALSE)
  prose <- rep(TRUE, length(lines))
  fence <- which(grepl("^```", lines))
  k <- 1L
  while (k <= length(fence)) {
    a <- fence[k]
    b <- if (k + 1L <= length(fence)) fence[k + 1L] else length(lines)
    prose[a:b] <- FALSE
    k <- k + 2L
  }
  if (!sum(prose)) .scg_stop(paste0("vacuous: zero prose lines in ", page))
  v <- character(0); bound <- 0L; marked <- 0L
  for (i in seq_along(lines)) {
    if (!prose[i]) next
    runs <- .scg_digit_runs(lines[i])
    if (!length(runs)) next
    if (grepl("<!-- ms-num", lines[i], fixed = TRUE)) {
      kind <- .scg_attr(lines[i], "kind")
      reason <- .scg_attr(lines[i], "reason")
      ok <- !is.na(kind) && kind %in% c("illustrative", "citation") &&
        !is.na(reason) && nzchar(reason) &&
        ((identical(kind, "illustrative") && grepl("synthetic", reason, fixed = TRUE)) ||
         (identical(kind, "citation") &&
          (grepl("PMID", reason, fixed = TRUE) || grepl("doi", reason, fixed = TRUE) ||
           grepl("external", reason, fixed = TRUE))))
      if (!ok) {
        v <- c(v, paste0("ms-num marker malformed at line ", i, ": kind=",
                        if (is.na(kind)) "<absent>" else kind))
        # a marker that fails its contract launders nothing: the numerals
        # still owe the census their witness bytes
        for (tk in runs) {
          if (!(tk %in% numset)) {
            v <- c(v, paste0("prose numeral not witness-bound: ", tk,
                            " (line ", i, ")"))
          }
        }
      } else {
        marked <- marked + length(runs)
      }
    } else {
      for (tk in runs) {
        if (tk %in% numset) bound <- bound + 1L
        else v <- c(v, paste0("prose numeral not witness-bound: ", tk, " (line ", i, ")"))
      }
    }
  }
  list(bound = bound, marked = marked, violations = v)
}

# CLI main: runs unless the sourcing face raised the shared marker.
if (!identical(Sys.getenv("MSUITER_TOOL_NO_MAIN", ""), "1")) {
  if (any(grepl("^--prose-check", .args))) {
    root <- scg_root()
    wd <- .scg_get("--witness-dir=", required = FALSE)
    wdir <- if (nzchar(wd)) wd else scg_witness_dir(root)
    page <- .scg_get("--page=", required = FALSE)
    if (!nzchar(page)) page <- file.path(root, "vignettes", "scenarios.Rmd")
    ns <- scg_numset(wdir)
    a <- scg_prose_audit(page, ns)
    cat(paste0("PROSE CENSUS: page=", basename(page), " census-tokens=", length(ns),
               " unmarked=", a$bound, " marked=", a$marked,
               " violations=", length(a$violations), "\n", sep = ""))
    for (v0 in a$violations) cat("VIOLATION: ", v0, "\n", sep = "")
    quit(status = if (length(a$violations)) 1L else 0L)
  }
  out <- .scg_get("--out=")
  root <- scg_root()
  der <- scg_derive(root)
  if (!dir.exists(out)) dir.create(out, recursive = TRUE)
  writeLines(paste0(der$rel, "\t", der$sha256, "\t", der$rows, "\t", der$cols),
             file.path(out, "manifest.tsv"))
  body <- scg_render(root)
  page <- c("<!doctype html>", "<html lang=\"en\">", "<head>",
            "<meta charset=\"utf-8\">",
            "<title>msuiter scenario witness gallery</title>", "</head>",
            "<body>", body, "</body>", "</html>")
  writeLines(page, file.path(out, "gallery.html"))
  cat(paste0("GALLERY CENSUS: witnesses=", nrow(der),
             " rows-total=", sum(as.integer(der$rows)),
             " columns-total=", sum(as.integer(der$cols)),
             " violations=0\n", sep = ""))
}
