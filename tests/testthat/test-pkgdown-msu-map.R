# test-pkgdown-msu-map.R: DS-2 MSU concept-map governance law (docs/site v1).
# docs/MSU-MAP.md is the function-to-concept-to-pillar-to-peer bridge the
# site's reference index links against. Its row set is NOT hand-maintained:
# this law re-derives it from the NAMESPACE bytes and pins row-set equality
# (missing, extra and duplicated rows are each named), the three-pillar
# vocabulary with a live resolvable anchor per row (path exists; path#slug
# heading re-computed from the heading bytes at test time -- a renamed or
# deleted heading reddens the row it anchors), the peer-cell shape
# (tool::function or NONE with a stated reason), and a non-vacuous census.
# Constructed-broken controls fire every rule; the constructed-perfect
# rebuild is the green control (dead-metric law).

# --- helpers (independent of the authoring tool) -------------------------------

.ds2_slug <- function(h) {
  h <- tolower(trimws(sub("^#+[[:space:]]*", "", h)))
  ch <- strsplit(h, "")[[1L]]
  keep <- ch[ch %in% c(letters, 0:9, " ", "-")]
  s <- paste0(keep, collapse = "")
  s <- gsub("  +", " ", s)
  s <- gsub(" ", "-", trimws(s))
  gsub("^-+|-+$", "", s)
}

.ds2_which_eq <- function(vec, s) {
  out <- integer(0)
  for (i in seq_along(vec)) if (identical(vec[i], s)) out <- c(out, i)
  out
}

.ds2_exports <- function(ns) {
  ex <- character(0)
  for (l in ns) if (startsWith(l, "export(") && endsWith(l, ")")) {
    ex <- c(ex, substr(l, 8L, nchar(l) - 1L))
  }
  ex
}

.ds2_cell_split <- function(line) {
  # manual pipe split: strsplit(x, "|") rides the regex engine, where "|" is
  # the empty-alternation metacharacter on this base.
  ch <- strsplit(line, "")[[1L]]
  cells <- character(0)
  cur <- character(0)
  for (tok in ch) {
    if (identical(tok, "|")) {
      cells <- c(cells, paste0(cur, collapse = ""))
      cur <- character(0)
    } else {
      cur <- c(cur, tok)
    }
  }
  cells <- c(cells, paste0(cur, collapse = ""))
  cells <- cells[seq(2L, length(cells) - 1L)]  # drop outer empties
  trimws(cells)
}

# slug set of every markdown heading in a file, or NULL when unreadable
.ds2_heading_slugs <- function(path) {
  if (!file.exists(path)) return(NULL)
  lines <- readLines(path, warn = FALSE)
  heads <- character(0)
  for (l in lines) if (startsWith(l, "#")) heads <- c(heads, .ds2_slug(l))
  heads
}

.ds2_law <- function(map_lines, ns, root) {
  v <- character(0)
  b <- .ds2_which_eq(map_lines, "<!-- msu-map:table-begin -->")
  e <- .ds2_which_eq(map_lines, "<!-- msu-map:table-end -->")
  if (length(b) != 1L || length(e) != 1L || b[1] >= e[1]) {
    return(list(violations = paste0("MSU-MAP table sentinels malformed ",
                "(begin hits=", length(b), " end hits=", length(e), ")"),
                rows = 0L, exports = 0L))
  }
  body <- map_lines[seq(b[1] + 1L, e[1] - 1L)]
  body <- body[vapply(body, function(l) startsWith(l, "|"), logical(1))]
  data_rows <- character(0)
  for (l in body) {
    first <- .ds2_cell_split(l)[1]
    is_sep <- nzchar(first) &&
      all(strsplit(first, "")[[1L]] %in% c("-", ":"))
    if (!identical(first, "function") && !is_sep) data_rows <- c(data_rows, l)
  }
  exports <- .ds2_exports(ns)
  if (length(data_rows) == 0L || length(exports) == 0L) {
    return(list(violations = paste0("vacuous census: data rows=",
                length(data_rows), " exports=", length(exports)),
                rows = length(data_rows), exports = length(exports)))
  }
  fn_seen <- character(0)
  for (l in data_rows) {
    cells <- .ds2_cell_split(l)
    if (length(cells) != 4L) {
      v <- c(v, paste0("row does not have 4 cells (", length(cells),
                       " found): ", substr(l, 1L, 60L)))
      next
    }
    fn <- cells[1]
    if (!.ds2_is_symbol(fn)) {
      v <- c(v, paste0("row key is not a symbol: ", fn))
      next
    }
    fn_seen <- c(fn_seen, fn)
    if (!fn %in% exports) {
      v <- c(v, paste0("row names a non-exported face: ", fn))
    }
    # concept cell
    if (nchar(cells[2]) < 3L || identical(tolower(cells[2]), tolower(fn))) {
      v <- c(v, paste0("concept cell hollow for row: ", fn))
    }
    # pillar + anchor cell: "<pillar> (<path>[#<slug>])"
    pc <- cells[3]
    op <- FALSE
    oppos <- 0L
    ch <- strsplit(pc, "")[[1L]]
    for (i in seq_along(ch)) if (identical(ch[i], "(")) {
      oppos <- i
      op <- TRUE
      break
    }
    if (!op) {
      v <- c(v, paste0("pillar cell carries no anchor parenthesis: ", fn))
      next
    }
    pillar <- trimws(substr(pc, 1L, oppos - 1L))
    if (!pillar %in% c("architecture", "performance", "scenarios")) {
      v <- c(v, paste0("pillar word not in the three-pillar vocabulary: ",
                       fn, " [", pillar, "]"))
    }
    anchor <- trimws(substr(pc, oppos + 1L, nchar(pc)))
    while (endsWith(anchor, ")")) {
      anchor <- trimws(substr(anchor, 1L, nchar(anchor) - 1L))
    }
    hash <- 0L
    ch2 <- strsplit(anchor, "")[[1L]]
    for (i in seq_along(ch2)) if (identical(ch2[i], "#")) {
      hash <- i
      break
    }
    rel <- if (hash == 0L) anchor else substr(anchor, 1L, hash - 1L)
    slug <- if (hash == 0L) NA_character_ else
      substr(anchor, hash + 1L, nchar(anchor))
    if (!nzchar(rel) || startsWith(rel, "/")) {
      v <- c(v, paste0("anchor is not a repo-relative path: ", fn, " [",
                       anchor, "]"))
      next
    }
    f <- file.path(root, rel)
    slugs <- .ds2_heading_slugs(f)
    if (is.null(slugs)) {
      v <- c(v, paste0("anchor file does not exist: ", fn, " [", rel, "]"))
      next
    }
    if (!is.na(slug) && !nzchar(slug)) {
      v <- c(v, paste0("anchor has an empty slug part: ", fn))
      next
    }
    if (!is.na(slug) && !slug %in% slugs) {
      v <- c(v, paste0("anchor slug does not resolve to a heading: ", fn,
                       " [", anchor, "]"))
    }
    # peer cell
    peer <- cells[4]
    if (startsWith(peer, "NONE")) {
      rest <- sub("^NONE[[:space:]]*--[[:space:]]*", "", peer)
      if (identical(rest, peer) ||
          length(strsplit(trimws(rest), " ")[[1L]]) < 2L) {
        v <- c(v, paste0("NONE peer cell without a stated reason: ", fn))
      }
    } else {
      ccol <- 0L
      ch3 <- strsplit(peer, "")[[1L]]
      for (i in seq_along(ch3)) if (identical(ch3[i], ":")) ccol <- ccol + 1L
      if (ccol != 2L || !grepl("::", peer, fixed = TRUE)) {
        v <- c(v, paste0("peer cell is neither NONE-with-reason nor ",
                         "tool::function: ", fn, " [", peer, "]"))
        next
      }
      bits <- strsplit(peer, "::")[[1L]]
      if (length(bits) != 2L || !bits[1] %in% c("sigminer", "sigprofiler") ||
          !.ds2_is_symbol(bits[2])) {
        v <- c(v, paste0("peer cell tool/function shape violated: ", fn,
                         " [", peer, "]"))
      }
    }
  }
  dup <- fn_seen[duplicated(fn_seen)]
  for (d in unique(dup)) v <- c(v, paste0("row listed twice: ", d))
  for (m in setdiff(exports, fn_seen)) v <- c(v, paste0("export has no row: ", m))
  list(violations = v, rows = length(fn_seen), exports = length(exports))
}

.ds2_is_symbol <- function(x) {
  if (!nzchar(x)) return(FALSE)
  ch <- strsplit(x, "")[[1L]]
  all(ch %in% c(LETTERS, letters, 0:9, ".", "_"))
}

# --- repository gate -------------------------------------------------------------

.ds2_repo_file <- function(rel) {
  if (is.na(.ms_root)) {
    skip("repository checkout not locatable (R CMD check context)")
  }
  f <- file.path(.ms_root, rel)
  if (!file.exists(f)) {
    skip(paste0(rel, " not available (R CMD check context)"))
  }
  f
}

.ds2_shipped <- function() {
  list(map = readLines(.ds2_repo_file("docs/MSU-MAP.md"), warn = FALSE),
       ns = readLines(.ds2_repo_file("NAMESPACE"), warn = FALSE),
       root = .ms_root)
}

# --- green half --------------------------------------------------------------------

test_that("DS-2 the shipped MSU-MAP single-covers NAMESPACE with live anchors and shaped peer cells", {
  d <- .ds2_shipped()
  r <- .ds2_law(d$map, d$ns, d$root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_identical(r$rows, r$exports)
  expect_gte(r$rows, 1L)
  cat("DS-2 CENSUS: map rows=", r$rows, " exports=", r$exports, "\n", sep = "")
})

# --- red half: constructed-broken controls -------------------------------------------

test_that("DS-2 a dropped row is named against its export", {
  d <- .ds2_shipped()
  drop <- NA_integer_
  for (i in seq_along(d$map)) {
    l <- d$map[i]
    if (startsWith(l, "| ") && identical(.ds2_cell_split(l)[1], "ms_sitrep")) {
      drop <- i
    }
  }
  expect_false(is.na(drop))
  r <- .ds2_law(d$map[-drop], d$ns, d$root)
  expect_true(any(grepl("export has no row: ms_sitrep", r$violations,
                        fixed = TRUE)))
})

test_that("DS-2 a duplicated row is named by the single-row rule", {
  d <- .ds2_shipped()
  hit <- which(startsWith(d$map, "| ms_sitrep |"))
  expect_length(hit, 1L)
  r <- .ds2_law(append(d$map, d$map[hit], after = hit[1]), d$ns, d$root)
  expect_true(any(vapply(r$violations, function(x) {
    grepl("row listed twice", x, fixed = TRUE) &&
      grepl("ms_sitrep", x, fixed = TRUE)
  }, logical(1))))
})

test_that("DS-2 a foreign pillar word names the row", {
  d <- .ds2_shipped()
  hit <- NA_integer_
  for (i in seq_along(d$map)) {
    l <- d$map[i]
    if (startsWith(l, "| ") && identical(.ds2_cell_split(l)[1], "ms_tally")) {
      hit <- i
    }
  }
  expect_false(is.na(hit))
  tampered <- d$map
  cells <- .ds2_cell_split(tampered[hit])
  tampered[hit] <- paste0("| ", cells[1], " | ", cells[2],
                          " | governance (", "docs/ARCHITECTURE.md", ") | ",
                          cells[4], " |")
  r <- .ds2_law(tampered, d$ns, d$root)
  expect_true(any(vapply(r$violations, function(x) {
    grepl("three-pillar vocabulary", x, fixed = TRUE) &&
      grepl("ms_tally", x, fixed = TRUE)
  }, logical(1))))
})

test_that("DS-2 a dead anchor file names the row", {
  d <- .ds2_shipped()
  hit <- which(startsWith(d$map, "| ms_tally |"))
  expect_length(hit, 1L)
  cells <- .ds2_cell_split(d$map[hit])
  tampered <- d$map
  tampered[hit] <- paste0("| ms_tally | ", cells[2],
                          " | architecture (docs/NOPE-DOES-NOT-EXIST.md) | ",
                          cells[4], " |")
  r <- .ds2_law(tampered, d$ns, d$root)
  expect_true(any(grepl("anchor file does not exist: ms_tally",
                        r$violations, fixed = TRUE)))
})

test_that("DS-2 a dead anchor slug names the row", {
  d <- .ds2_shipped()
  hit <- which(startsWith(d$map, "| ms_tally |"))
  expect_length(hit, 1L)
  cells <- .ds2_cell_split(d$map[hit])
  tampered <- d$map
  tampered[hit] <- paste0("| ms_tally | ", cells[2],
                          " | architecture (docs/ARCHITECTURE.md#heading-that-cannot-exist) | ",
                          cells[4], " |")
  r <- .ds2_law(tampered, d$ns, d$root)
  expect_true(any(grepl("does not resolve to a heading: ms_tally",
                        r$violations, fixed = TRUE)))
})

test_that("DS-2 malformed peer cells name the row (both banned shapes)", {
  d <- .ds2_shipped()
  hit <- which(startsWith(d$map, "| ms_tally |"))
  expect_length(hit, 1L)
  cells <- .ds2_cell_split(d$map[hit])
  mk <- function(peer) {
    t2 <- d$map
    t2[hit] <- paste0("| ms_tally | ", cells[2], " | ", cells[3], " | ",
                      peer, " |")
    t2
  }
  r1 <- .ds2_law(mk("sigminer"), d$ns, d$root)
  expect_true(any(grepl("neither NONE-with-reason nor tool::function: ms_tally",
                        r1$violations, fixed = TRUE)))
  r2 <- .ds2_law(mk("NONE"), d$ns, d$root)
  expect_true(any(grepl("without a stated reason: ms_tally",
                        r2$violations, fixed = TRUE)))
  r3 <- .ds2_law(mk("otherpkg::thing"), d$ns, d$root)
  expect_true(any(grepl("tool/function shape violated: ms_tally",
                        r3$violations, fixed = TRUE)))
})

test_that("DS-2 the empty table trips the vacuous census rule", {
  d <- .ds2_shipped()
  b <- .ds2_which_eq(d$map, "<!-- msu-map:table-begin -->")
  e <- .ds2_which_eq(d$map, "<!-- msu-map:table-end -->")
  expect_length(b, 1L)
  expect_length(e, 1L)
  emptied <- append(d$map[seq(1L, b[1])], d$map[e[1]], after = b[1])
  r <- .ds2_law(emptied, d$ns, d$root)
  expect_true(any(grepl("vacuous census", r$violations, fixed = TRUE)))
})

test_that("DS-2 the constructed-perfect rebuild greens the law (live control)", {
  d <- .ds2_shipped()
  exports <- .ds2_exports(d$ns)
  expect_gte(length(exports), 1L)
  ctrl <- c("<!-- msu-map:table-begin -->",
            "| function | MSU concept served | paper pillar (anchor) | peer counterpart |",
            "|---|---|---|---|",
            paste0("| ", exports, " | control row face serving governance |",
                   " architecture (docs/ARCHITECTURE.md#",
                   .ds2_slug("## 1. The system-layering overview"),
                   ") | NONE -- governance control row |"),
            "<!-- msu-map:table-end -->")
  r <- .ds2_law(ctrl, d$ns, d$root)
  expect_identical(r$violations, character(0),
                   info = paste0(r$violations, collapse = "\n"))
  expect_identical(r$rows, length(exports))
})
