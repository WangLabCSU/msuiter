# peer-evidence.R -- DS-3 US-G2 peer-evidence page tool (docs/site v3).
# Renders the peer-evidence face STRICTLY from the sanctioned committed
# witness corpus: bench/results/*/witnesses plus
# bench/scenarios/out/compare_sweep.csv. Every number the page asserts rides
# inside a <span class="peer-value" data-col="..." data-witness="REL">
# marker whose value is a verbatim byte substring of the named witness --
# the law (tests/testthat/test-peer-evidence.R) re-audits that demand span by
# span. Provenance stamps are in-process sha256 (digest file=TRUE, never an
# external shasum) plus the campaign directory name. Scored sweep columns
# fail closed when absent (a name-keyed join that silently zero-fills is a
# dead metric and is refused). No benchmarking, no recomputation, no
# hand-typed numerics.
# usage: Rscript tools/peer-evidence.R --out=<dir> [--root=<dir>]

spe_SCORED <- c("tau", "precision", "recall", "f1")
spe_SEALED_KEYS <- c("wall", "cpu", "floor_projection", "floor_ratio")

.args <- commandArgs(FALSE)
.args <- as.character(.args[nzchar(as.character(.args))])
.spe_get <- function(pref, required = TRUE) {
  hit <- grepl(paste0("^", pref), .args)
  if (!any(hit)) {
    if (required) stop("missing required argument ", pref, "<value>",
                       domain = NA)
    return("")
  }
  sub(pref, "", .args[which(hit)[1L]])
}

.spe_stop <- function(msg) stop(msg, domain = NA, call. = FALSE)

spe_root <- function() {
  root <- .spe_get("--root=", required = FALSE)
  if (nzchar(root)) return(normalizePath(root))
  p <- normalizePath(getwd())
  repeat {
    if (file.exists(file.path(p, "DESCRIPTION"))) return(p)
    up <- dirname(p)
    if (identical(up, p)) {
      .spe_stop("vacuous: no package root above the working directory")
    }
    p <- up
  }
}

spe_roster <- function(root) {
  wroot <- file.path(root, "bench", "results")
  rel <- character(0)
  if (dir.exists(wroot)) {
    allf <- list.files(wroot, recursive = TRUE, full.names = FALSE)
    allf <- allf[!endsWith(allf, "/")]   # this base's recursive walk also lists dirs
    hit <- allf[grepl("/witnesses/", paste0("/", allf), fixed = TRUE)]
    rel <- paste0("bench/results/", hit)
  }
  sweep <- spe_SWEEP_REL
  if (file.exists(file.path(root, sweep))) rel <- c(rel, sweep)
  rel <- sort(unique(rel))
  rel <- rel[!endsWith(rel, "/")]
  rel <- rel[vapply(rel, function(r) file.exists(file.path(root, r)),
                    logical(1), USE.NAMES = FALSE)]
  if (!length(rel)) {
    .spe_stop(paste0("vacuous: sanctioned peer corpus is empty under ", wroot))
  }
  rel
}

spe_SWEEP_REL <- "bench/scenarios/out/compare_sweep.csv"

spe_sha <- function(f) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    .spe_stop("digest namespace unavailable: witness hashing is in-process by law")
  }
  h <- digest::digest(f, algo = "sha256", file = TRUE)
  if (length(h) != 1L || nchar(h) != 64L ||
      !all(strsplit(h, "")[[1L]] %in% strsplit("0123456789abcdef", "")[[1L]])) {
    .spe_stop(paste0("digest desync: malformed sha256 for ", f))
  }
  h
}

spe_campaign <- function(rel) {
  parts <- strsplit(rel, "/", fixed = TRUE)[[1L]]
  w <- which(parts == "witnesses")
  if (length(w)) parts[max(1L, w[1L] - 1L)] else "atlas-sweep"
}

spe_manifest <- function(root) {
  rel <- spe_roster(root)
  sha <- vapply(rel, function(r) spe_sha(file.path(root, r)), character(1),
                USE.NAMES = FALSE)
  rows <- vapply(rel, function(r)
    as.character(length(readLines(file.path(root, r), warn = FALSE))),
    character(1), USE.NAMES = FALSE)
  data.frame(rel = rel, campaign = vapply(rel, spe_campaign, character(1),
                                          USE.NAMES = FALSE),
             sha256 = sha, rows = rows, stringsAsFactors = FALSE)
}

# quote-aware single-comma cell walk
spe_cells <- function(line) {
  ch <- strsplit(line, "")[[1L]]
  n <- length(ch)
  out <- character(0); cur <- character(0); quoted <- FALSE
  i <- 1L
  while (i <= n) {
    c0 <- ch[[i]]
    if (identical(c0, "\"")) {
      if (quoted && i < n && identical(ch[[i + 1L]], "\"")) {
        cur <- c(cur, "\""); i <- i + 2L; next
      }
      quoted <- !quoted
    } else if (!quoted && identical(c0, ",")) {
      out <- c(out, paste0(cur, collapse = "")); cur <- character(0)
    } else cur <- c(cur, c0)
    i <- i + 1L
  }
  c(out, paste0(cur, collapse = ""))
}

# Fail-closed scored-column read: an absent scored column is a DEAD METRIC
# and is named, never zero-filled.
spe_sweep <- function(csv) {
  if (!file.exists(csv)) .spe_stop(paste0("no sweep witness: ", csv))
  lines <- readLines(csv, warn = FALSE)
  if (length(lines) < 2L) {
    .spe_stop(paste0("vacuous: sweep witness carries no data rows: ", csv))
  }
  names <- spe_cells(lines[1L])
  rows <- lapply(lines[-1L], spe_cells)
  for (col in spe_SCORED) {
    if (!col %in% names) {
      .spe_stop(paste0("dead column: ", col,
                       " absent from the sweep header -- refusing to zero-fill"))
    }
  }
  list(names = names, rows = rows, csv = normalizePath(csv))
}

spe_escape <- function(s) {
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s
}

# guarded fixed-token position scan: this base's gregexpr speaks no-match as
# a -1 vector with a -1 match.length attribute, not NULL (measured 2026-11-02)
.spe_gscan <- function(pat, text) {
  g <- gregexpr(pat, text, fixed = TRUE)[[1L]]
  if (is.null(g)) return(NULL)
  starts <- as.integer(g)
  lens <- as.integer(attr(g, "match.length"))
  if (!length(starts) || identical(lens, -1L) || identical(starts, -1L)) {
    return(NULL)
  }
  if (any(starts < 1L) || any(is.na(lens)) || any(lens < 1L)) return(NULL)
  list(starts = starts, lens = lens)
}

# verbatim "key":value extractions from compact-JSON witness bytes
.spe_json_values <- function(bytes, key) {
  hit <- .spe_gscan(paste0("\"", key, "\":"), bytes)
  if (is.null(hit)) return(character(0))
  out <- character(0)
  for (i in seq_along(hit$starts)) {
    a <- hit$starts[i] + hit$lens[i]
    rest <- substr(bytes, a, min(nchar(bytes), a + 63L))
    ch <- strsplit(rest, "")[[1L]]
    val <- character(0)
    for (c0 in ch) {
      if (c0 %in% c(",", "}", "]", "\n")) break
      val <- c(val, c0)
    }
    tok <- trimws(paste0(val, collapse = ""))
    if (nzchar(tok)) out <- c(out, tok)
  }
  out
}

.spe_span <- function(col, rel, value) {
  paste0("<span class=\"peer-value\" data-col=\"", col, "\" data-witness=\"",
         rel, "\">", spe_escape(value), "</span>")
}

spe_render <- function(root) {
  rel <- spe_roster(root)
  man <- spe_manifest(root)
  out <- character(0)
  campaigns <- unique(man$campaign)
  for (camp in campaigns) {
    rows <- man[man$campaign == camp, ]
    out <- c(out,
             paste0("<div class=\"peer-card\" data-campaign=\"", camp, "\">"),
             paste0("<h3>", spe_escape(camp), "</h3>"))
    for (i in seq_len(nrow(rows))) {
      out <- c(out, paste0("<p class=\"peer-witness\" data-witness=\"",
                           rows$rel[i], "\">", spe_escape(rows$rel[i]),
                           " <code class=\"witness-sha\">", rows$sha256[i],
                           "</code> rows=", rows$rows[i], "</p>"))
    }
    sealed <- character(0)
    for (r in rows$rel) {
      base <- basename(r)
      if (!(grepl("^[.]?arm_", base) || grepl("^probe_", base))) next
      bytes <- paste0(readLines(file.path(root, r), warn = FALSE),
                      collapse = "\n")
      for (key in spe_SEALED_KEYS) {
        for (tok in .spe_json_values(bytes, key)) {
          sealed <- c(sealed, paste0("<p class=\"peer-sealed\" data-key=\"",
                                      key, "\">", key, " ",
                                      .spe_span(key, r, tok), "</p>"))
        }
      }
    }
    out <- c(out, sealed, "</div>")
  }
  sw <- spe_sweep(file.path(root, spe_SWEEP_REL))
  out <- c(out, "<table class=\"sweep-table\">",
           paste0("<tr>",
                  paste0(vapply(sw$names, function(nm)
                    paste0("<th>", spe_escape(nm), "</th>"),
                    character(1), USE.NAMES = FALSE), collapse = ""),
                  "</tr>"))
  for (rw in sw$rows) {
    cells <- character(0)
    for (j in seq_along(sw$names)) {
      nm <- sw$names[j]
      cells <- c(cells, if (nm %in% spe_SCORED) {
        paste0("<td>", .spe_span(nm, spe_SWEEP_REL, rw[j]), "</td>")
      } else {
        paste0("<td>", spe_escape(rw[j]), "</td>")
      })
    }
    out <- c(out, paste0("<tr>", paste0(cells, collapse = ""), "</tr>"))
  }
  out <- c(out, "</table>")
  out
}

# CLI main: runs unless the sourcing face raised the shared marker.
if (!identical(Sys.getenv("MSUITER_TOOL_NO_MAIN", ""), "1")) {
  out <- .spe_get("--out=")
  root <- spe_root()
  man <- spe_manifest(root)
  if (!dir.exists(out)) dir.create(out, recursive = TRUE)
  writeLines(paste0(man$rel, "\t", man$campaign, "\t", man$sha256, "\t",
                     man$rows), file.path(out, "manifest.tsv"))
  body <- spe_render(root)
  spanhit <- .spe_gscan("<span class=\"peer-value\" data-col=",
                        paste0(body, collapse = "\n"))
  nspans <- if (is.null(spanhit)) 0L else length(spanhit$starts)
  page <- c("<!doctype html>", "<html lang=\"en\">", "<head>",
            "<meta charset=\"utf-8\">",
            "<title>msuiter peer evidence: sealed witness face</title>",
            "</head>", "<body>", body, "</body>", "</html>")
  writeLines(page, file.path(out, "peer.html"))
  cat(paste0("PEER CENSUS: campaigns=", length(unique(man$campaign)),
             " witnesses=", nrow(man), " peer-values=", nspans,
             " scored-cols=", length(spe_SCORED), " dead=0\n", sep = ""))
}
