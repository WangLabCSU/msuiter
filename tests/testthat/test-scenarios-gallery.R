# test-scenarios-gallery.R: DS-3 US-G1 scenario-gallery page laws (docs/site v3).
# The gallery galleries the committed witnesses under bench/scenarios/out/: one
# card per file, each carrying an in-process sha256 provenance stamp, a
# row/column census and a verbatim excerpt. Every digit the page prints is
# re-derived from the committed bytes at build time by tools/scenarios-gallery.R
# -- the page ships no hand-typed numeric. This file audits the tool's own
# output: byte-reproducible re-derivation (two runs, one manifest),
# card-to-file naming, stamp-to-disk equality and census-to-wc equality. The
# audit is fail-closed: an empty witness tree reddens (vacuous-green ban), a
# tampered copy is named, a dropped card is named, a ghost card is named, and
# the re-derivation of the committed tree must pass clean (firing controls).

# --- tool access ------------------------------------------------------------------

.sg_tool <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "tools", "scenarios-gallery.R")
  if (!file.exists(f)) stop("tools/scenarios-gallery.R missing (US-G1 defect)")
  f
}

# Source the tool without running its CLI main: the MSUITER_TOOL_NO_MAIN
# marker is the source-vs-invoke discriminator the tool itself honors.
.sg_env <- function() {
  f <- .sg_tool()
  e <- new.env(parent = globalenv())
  Sys.setenv(MSUITER_TOOL_NO_MAIN = "1")
  on.exit(Sys.unsetenv("MSUITER_TOOL_NO_MAIN"), add = TRUE)
  source(f, local = e)
  need <- c("scg_roster", "scg_derive", "scg_cards", "scg_render")
  for (n in need) {
    if (!exists(n, envir = e, inherits = FALSE)) {
      stop("scenarios-gallery tool lost its callable face: ", n)
    }
  }
  e
}

.sg_cli <- function(root, out) {
  res <- suppressWarnings(system2(.ms_rscript(),
                                  c(.sg_tool(), paste0("--out=", out),
                                    paste0("--root=", root)),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  list(status = if (is.null(st)) 0L else as.integer(st),
       out = paste0(as.character(res), collapse = "\n"))
}

# --- in-process disk re-derivation (law-side twin; never an external shasum) ------

.sg_disk_sha <- function(f) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("digest namespace unavailable: witness hashing is in-process by law")
  }
  digest::digest(f, algo = "sha256", file = TRUE)
}

.sg_delim_for <- function(rel) {
  if (endsWith(rel, ".tsv")) "\t" else ","
}

# --- the audit: manifest rows vs disk bytes (fail-closed both directions) ---------

.sg_audit <- function(manifest_lines, root) {
  outdir <- file.path(root, "bench", "scenarios", "out")
  files <- if (dir.exists(outdir)) sort(list.files(outdir)) else character(0)
  if (!length(files)) {
    return(list(violations = paste0("vacuous: zero witness files under ", outdir),
                n = 0L))
  }
  v <- character(0)
  rels <- character(0)
  for (m in manifest_lines) {
    p <- strsplit(m, "\t", fixed = TRUE)[[1L]]
    if (length(p) != 4L) {
      v <- c(v, paste0("malformed manifest row: ", m))
      next
    }
    rels <- c(rels, p[1L])
    f <- file.path(outdir, p[1L])
    if (!file.exists(f)) {
      v <- c(v, paste0("manifest card with no witness on disk: ", p[1L]))
      next
    }
    if (!identical(p[2L], .sg_disk_sha(f))) {
      v <- c(v, paste0("hash off disk bytes: ", p[1L]))
    }
    lines <- readLines(f, warn = FALSE)
    if (!identical(p[3L], as.character(length(lines)))) {
      v <- c(v, paste0("row census off disk: ", p[1L], " says ", p[3L],
                       " disk ", as.character(length(lines))))
    }
    if (!identical(p[4L], .sg_col_count(lines[1L], .sg_delim_for(p[1L])))) {
      v <- c(v, paste0("column census off header: ", p[1L]))
    }
  }
  for (f in files) {
    if (!f %in% rels) v <- c(v, paste0("witness has no card: ", f))
  }
  dup <- vapply(rels, function(x) sum(rels == x) > 1L, logical(1),
                USE.NAMES = FALSE)
  if (any(dup)) {
    v <- c(v, paste0("duplicate card in the manifest: ",
                     paste0(unique(rels[dup]), collapse = ", ")))
  }
  list(violations = v, n = length(files))
}

# Header cell count of one line: quote-aware char walk over the delimiter.
.sg_col_count <- function(line, delim) {
  ch <- strsplit(line, "")[[1L]]
  n <- length(ch)
  cells <- 1L
  quoted <- FALSE
  i <- 1L
  while (i <= n) {
    c0 <- ch[[i]]
    if (identical(c0, "\"")) {
      if (quoted && i < n && identical(ch[[i + 1L]], "\"")) {
        i <- i + 2L
        next
      }
      quoted <- !quoted
    } else if (!quoted && identical(c0, delim)) {
      cells <- cells + 1L
    }
    i <- i + 1L
  }
  as.character(cells)
}

# --- card scans over the rendered page (fixed-token walks) -------------------------

# guarded fixed-token position scan: this base's gregexpr speaks no-match as
# a -1 vector with a -1 match.length attribute, not NULL (measured 2026-11-02)
.sg_gscan <- function(pat, text) {
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

# fixed-token between-walk: this base's gregexpr carries match starts as
# VALUES with a per-match match.length attribute (regexpr position attrs are
# unreliable under fixed -- measured 2026-11-02, renamed-R base quirks).
.sg_between_all <- function(text, open, close) {
  out <- character(0)
  g1 <- .sg_gscan(open, text)
  g2 <- .sg_gscan(close, text)
  if (is.null(g1) || is.null(g2)) return(out)
  os <- g1$starts
  ol <- g1$lens
  cs <- g2$starts
  for (i in seq_along(os)) {
    a <- os[i] + ol[i]
    k <- which(cs >= a)
    if (!length(k)) break
    out <- c(out, substr(text, a, cs[k[1L]] - 1L))
  }
  out
}

# --- site locator (shared posture with the DS-2 built-tree halves) ------------------

.sg_site_dir <- function() {
  if (is.na(.ms_root)) return(NA_character_)
  sd <- Sys.getenv("MSUITER_DS2_SITE_DIR", "")
  if (nzchar(sd) && dir.exists(sd)) return(normalizePath(sd))
  cand <- file.path(.ms_root, "docs", "dev")
  if (file.exists(file.path(cand, "reference", "index.html")) &&
      file.exists(file.path(cand, "articles", "index.html"))) cand else NA_character_
}

# --- green halves -------------------------------------------------------------------

test_that("US-G1 the gallery manifest re-derives byte-for-byte across two runs", {
  .sg_tool()
  e <- .sg_env()
  root <- .ms_root
  d1 <- e$scg_derive(root)
  d2 <- e$scg_derive(root)
  expect_identical(d1, d2)
  o1 <- tempfile("sg-m1-"); o2 <- tempfile("sg-m2-")
  on.exit(unlink(c(o1, o2), recursive = TRUE), add = TRUE)
  r1 <- .sg_cli(root, o1)
  r2 <- .sg_cli(root, o2)
  expect_identical(r1$status, 0L, info = r1$out)
  expect_identical(r2$status, 0L, info = r2$out)
  m1 <- readLines(file.path(o1, "manifest.tsv"), warn = FALSE)
  m2 <- readLines(file.path(o2, "manifest.tsv"), warn = FALSE)
  expect_identical(m1, m2)
  expect_identical(length(m1), length(e$scg_roster(root)))
  hex <- strsplit("0123456789abcdef", "")[[1L]]
  for (m in m1) {
    p <- strsplit(m, "\t", fixed = TRUE)[[1L]]
    expect_identical(nchar(p[2L]), 64L)
    expect_true(all(strsplit(p[2L], "")[[1L]] %in% hex))
  }
  cat("US-G1 DERIVATION CENSUS: witnesses=", length(m1), " runs=2 stable=yes\n",
      sep = "")
})

test_that("US-G1 every card names its witness and its stamps match the disk bytes", {
  .sg_tool()
  e <- .sg_env()
  root <- .ms_root
  cards <- e$scg_render(root)
  expect_gte(length(cards), 1L)
  text <- paste0(cards, collapse = "\n")
  rels <- .sg_between_all(text, "data-witness=\"", "\"")
  roster <- e$scg_roster(root)
  expect_identical(sort(rels), sort(roster))
  shas <- .sg_between_all(text, "<code class=\"witness-sha\">", "<")
  expect_identical(length(shas), length(roster))
  for (f in roster) {
    i <- which(rels == f)
    expect_length(i, 1L)
    expect_identical(shas[i], .sg_disk_sha(file.path(root, "bench", "scenarios",
                                                      "out", f)),
                     info = paste0("stamp off disk: ", f))
  }
  rowstamps <- .sg_between_all(text, "rows=", " ")
  expect_identical(length(rowstamps), length(roster))
  for (i in seq_along(roster)) {
    f <- file.path(root, "bench", "scenarios", "out", roster[i])
    expect_identical(rowstamps[i], as.character(length(readLines(f, warn = FALSE))),
                     info = paste0("row census off wc: ", roster[i]))
  }
  expect_true(grepl("</table>", text, fixed = TRUE))
  cat("US-G1 CARD CENSUS: cards=", length(rels), " stamps-verified=", length(shas),
      " violations=0\n", sep = "")
})

test_that("US-G1 the built gallery page (when the lane site is present) carries every card", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sd <- .sg_site_dir()
  if (is.na(sd)) skip("no lane-built site tree (R CMD check context)")
  e <- .sg_env()
  page <- file.path(sd, "articles", "scenarios-gallery.html")
  if (!file.exists(page)) {
    stop("the lane-built site lacks articles/scenarios-gallery.html (US-G1 defect)")
  }
  html <- paste0(readLines(page, warn = FALSE), collapse = "\n")
  rels <- .sg_between_all(html, "data-witness=\"", "\"")
  expect_identical(sort(rels), sort(e$scg_roster(.ms_root)))
  cat("US-G1 BUILT CENSUS: cards=", length(rels), " violations=0\n", sep = "")
})

# --- red halves: firing controls -------------------------------------------------------

test_that("US-G1 a tampered witness copy reddens the audit and is named", {
  .sg_tool()
  e <- .sg_env()
  d <- e$scg_derive(.ms_root)
  man <- paste0(d$rel, "\t", d$sha256, "\t", d$rows, "\t", d$cols)
  a0 <- .sg_audit(man, .ms_root)
  expect_identical(a0$violations, character(0),
                   info = paste0(a0$violations, collapse = "\n"))
  expect_gte(a0$n, 1L)
  fake <- tempfile("sg-tamper-")
  dir.create(file.path(fake, "bench", "scenarios", "out"), recursive = TRUE)
  file.copy(list.files(file.path(.ms_root, "bench", "scenarios", "out"),
                       full.names = TRUE),
             file.path(fake, "bench", "scenarios", "out"))
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  victim <- file.path(fake, "bench", "scenarios", "out", "association.csv")
  writeLines(c(readLines(victim, warn = FALSE), '"SBS9",1,1,1,0.5,0.5,TRUE'),
             victim)
  a1 <- .sg_audit(man, fake)
  expect_true(any(grepl("hash off disk bytes: association.csv", a1$violations,
                        fixed = TRUE)))
  expect_true(any(grepl("row census off disk: association.csv", a1$violations,
                        fixed = TRUE)))
})

test_that("US-G1 dropping a card reddens the audit and is named", {
  .sg_tool()
  e <- .sg_env()
  d <- e$scg_derive(.ms_root)
  man <- paste0(d$rel, "\t", d$sha256, "\t", d$rows, "\t", d$cols)
  victim <- d$rel[3L]
  kept <- man[!startsWith(man, paste0(victim, "\t"))]
  expect_length(kept, length(man) - 1L)
  a <- .sg_audit(kept, .ms_root)
  expect_true(any(grepl(paste0("witness has no card: ", victim),
                        a$violations, fixed = TRUE)))
})

test_that("US-G1 a ghost card with no witness on disk is named", {
  .sg_tool()
  e <- .sg_env()
  d <- e$scg_derive(.ms_root)
  man <- c(paste0(d$rel, "\t", d$sha256, "\t", d$rows, "\t", d$cols),
           paste0("ghost_witness.csv\t0123456789abcdef0123456789abcdef",
                  "0123456789abcdef0123456789abcdef\t1\t1"))
  a <- .sg_audit(man, .ms_root)
  expect_true(any(grepl("manifest card with no witness on disk: ghost_witness.csv",
                        a$violations, fixed = TRUE)))
})

test_that("US-G1 an empty witness tree is vacuous-red, never empty-green", {
  .sg_tool()
  fake <- tempfile("sg-empty-")
  dir.create(file.path(fake, "bench", "scenarios", "out"), recursive = TRUE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  a <- .sg_audit(character(0), fake)
  expect_true(any(grepl("vacuous", a$violations, fixed = TRUE)))
  out <- tempfile("sg-empty-cli-")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  r <- .sg_cli(fake, out)
  expect_true(r$status != 0L, info = "the CLI accepted an empty witness tree")
  expect_true(grepl("vacuous", r$out, fixed = TRUE))
})
