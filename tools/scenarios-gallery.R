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

# CLI main: runs unless the sourcing face raised the shared marker.
if (!identical(Sys.getenv("MSUITER_TOOL_NO_MAIN", ""), "1")) {
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
