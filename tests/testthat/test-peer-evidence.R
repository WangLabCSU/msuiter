# test-peer-evidence.R: DS-3 US-G2 peer-evidence witness-only law (docs/site v3).
# Peer numbers enter the site ONLY as bytes of the sanctioned committed
# corpus: bench/results/*/witnesses plus bench/scenarios/out/compare_sweep.csv.
# The page tool (tools/peer-evidence.R) renders every such number inside a
# <span class="peer-value" data-col="..." data-witness="REL"> marker; this
# file re-parses the rendered output and demands, span by span, that the
# value is a byte of the very witness file the span cites -- membership in a
# hand roster is not enough. Dead-metric law: every scored sweep column
# (tau, precision, recall, f1) is proved LIVE by a constructed-perfect
# witness (the column rendered at its perfect value) and by the tool's
# refusal to zero-fill a removed column (each refusal a firing control).
# Provenance stamps (sha256 + campaign dir) must re-derive stably. An empty
# corpus is vacuous-red, never empty-green.

# --- tool access ------------------------------------------------------------------

.pe_tool <- function() {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  f <- file.path(.ms_root, "tools", "peer-evidence.R")
  if (!file.exists(f)) stop("tools/peer-evidence.R missing (US-G2 defect)")
  f
}

.pe_env <- function() {
  f <- .pe_tool()
  e <- new.env(parent = globalenv())
  Sys.setenv(MSUITER_TOOL_NO_MAIN = "1")
  on.exit(Sys.unsetenv("MSUITER_TOOL_NO_MAIN"), add = TRUE)
  source(f, local = e)
  need <- c("spe_roster", "spe_manifest", "spe_sweep", "spe_render")
  for (n in need) {
    if (!exists(n, envir = e, inherits = FALSE)) {
      stop("peer-evidence tool lost its callable face: ", n)
    }
  }
  e
}

.pe_cli <- function(root, out) {
  res <- suppressWarnings(system2(.ms_rscript(),
                                  c(.pe_tool(), paste0("--out=", out),
                                    paste0("--root=", root)),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(res, "status")
  list(status = if (is.null(st)) 0L else as.integer(st),
       out = paste0(as.character(res), collapse = "\n"))
}

.pe_disk_sha <- function(f) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("digest namespace unavailable: witness hashing is in-process by law")
  }
  digest::digest(f, algo = "sha256", file = TRUE)
}

# guarded fixed-token position scan: this base's gregexpr speaks no-match as
# a -1 vector with a -1 match.length attribute, not NULL (measured 2026-11-02)
.pe_gscan <- function(pat, text) {
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

# fixed-token between-walk (this base's gregexpr carries starts as VALUES)
.pe_between_all <- function(text, open, close) {
  out <- character(0)
  g1 <- .pe_gscan(open, text)
  g2 <- .pe_gscan(close, text)
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

# --- the span scan: (col, rel, value) triples the page asserts ----------------------

.pe_SPAN_OPEN <- "<span class=\"peer-value\" data-col=\""

.pe_spans <- function(text) {
  g <- .pe_gscan(.pe_SPAN_OPEN, text)
  if (is.null(g)) {
    return(data.frame(col = character(0), rel = character(0),
                      value = character(0), stringsAsFactors = FALSE))
  }
  starts <- g$starts
  olen <- g$lens
  gq <- .pe_gscan("\"", text)
  gw <- .pe_gscan("data-witness=\"", text)
  ge <- .pe_gscan("</span>", text)
  if (is.null(gq) || is.null(gw) || is.null(ge)) {
    stop("malformed page: a peer-value span rides without its landmarks")
  }
  qs <- gq$starts
  ws <- gw$starts
  wl <- gw$lens
  es <- ge$starts
  nxt <- function(cands, floor_pos) {
    k <- which(cands >= floor_pos)
    if (length(k)) cands[k[1L]] else NA_integer_
  }
  cols <- character(0); rels <- character(0); vals <- character(0)
  for (i in seq_along(starts)) {
    a <- starts[i] + olen[i]
    q1 <- nxt(qs, a)
    if (is.na(q1)) break
    col <- substr(text, a, q1 - 1L)
    w1 <- nxt(ws, q1 + 1L)
    if (is.na(w1)) break
    ra <- w1 + wl[1L]
    q3 <- nxt(qs, ra)
    if (is.na(q3)) break
    rel <- substr(text, ra, q3 - 1L)
    e1 <- nxt(es, q3)
    if (is.na(e1)) break
    cols <- c(cols, col)
    rels <- c(rels, rel)
    vals <- c(vals, substr(text, q3 + 2L, e1 - 1L))
  }
  data.frame(col = cols, rel = rels, value = vals, stringsAsFactors = FALSE)
}

# --- the sanctioned corpus + the audit -------------------------------------------------

.pe_corpus <- function(root) {
  wroot <- file.path(root, "bench", "results")
  rel <- character(0)
  if (dir.exists(wroot)) {
    allf <- list.files(wroot, recursive = TRUE, full.names = FALSE)
    allf <- allf[!endsWith(allf, "/")]
    hit <- allf[grepl("/witnesses/", paste0("/", allf), fixed = TRUE)]
    rel <- c(rel, paste0("bench/results/", hit))
  }
  sweep <- "bench/scenarios/out/compare_sweep.csv"
  if (file.exists(file.path(root, sweep))) rel <- c(rel, sweep)
  rel <- sort(unique(rel))
  rel[vapply(rel, function(r) file.exists(file.path(root, r)), logical(1),
             USE.NAMES = FALSE)]
}

.pe_SWEEP_REL <- "bench/scenarios/out/compare_sweep.csv"

.pe_audit <- function(rendered, root) {
  corpus <- .pe_corpus(root)
  if (!length(corpus)) {
    return(list(violations = paste0("vacuous: sanctioned peer corpus is empty ",
                                    "under ", file.path(root, "bench", "results")),
                spans = 0L))
  }
  sp <- .pe_spans(paste0(rendered, collapse = "\n"))
  if (!nrow(sp)) {
    return(list(violations = "vacuous: the rendered page asserts no peer byte",
                spans = 0L))
  }
  v <- character(0)
  for (i in seq_len(nrow(sp))) {
    f <- file.path(root, sp$rel[i])
    if (!sp$rel[i] %in% corpus || !file.exists(f)) {
      v <- c(v, paste0("peer span cites a non-sanctioned witness: ", sp$rel[i]))
      next
    }
    bytes <- paste0(readLines(f, warn = FALSE), collapse = "\n")
    if (!nzchar(sp$value[i]) || !grepl(sp$value[i], bytes, fixed = TRUE)) {
      v <- c(v, paste0("peer numeric off the witness bytes: ", sp$rel[i],
                       " -- ", sp$value[i]))
    }
  }
  list(violations = v, spans = nrow(sp))
}

# --- sweep re-derivation (law-side independent quote-aware parse) -----------------------

.pe_SCORED <- c("tau", "precision", "recall", "f1")

.pe_cells <- function(line) {
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

.pe_sweep_rows <- function(lines) {
  list(header = .pe_cells(lines[1L]),
       rows = lapply(lines[-1L], .pe_cells))
}

# --- site locator (DS-2 shared posture) --------------------------------------------------

.pe_site_dir <- function() {
  if (is.na(.ms_root)) return(NA_character_)
  sd <- Sys.getenv("MSUITER_DS2_SITE_DIR", "")
  if (nzchar(sd) && dir.exists(sd)) return(normalizePath(sd))
  cand <- file.path(.ms_root, "docs", "dev")
  if (file.exists(file.path(cand, "reference", "index.html")) &&
      file.exists(file.path(cand, "articles", "index.html"))) cand else NA_character_
}

# --- green halves -------------------------------------------------------------------------

test_that("US-G2 every rendered peer-value span is a byte of the witness it cites", {
  .pe_tool()
  e <- .pe_env()
  rendered <- e$spe_render(.ms_root)
  expect_gte(length(rendered), 1L)
  a <- .pe_audit(rendered, .ms_root)
  expect_identical(a$violations, character(0),
                   info = paste0(a$violations, collapse = "\n"))
  expect_gte(a$spans, 8L)
  cat("US-G2 WITNESS-ONLY CENSUS: spans=", a$spans, " off-corpus=0 off-bytes=0\n",
      sep = "")
})

test_that("US-G2 provenance stamps re-derive stably and match the disk bytes", {
  .pe_tool()
  e <- .pe_env()
  m1 <- e$spe_manifest(.ms_root)
  m2 <- e$spe_manifest(.ms_root)
  expect_identical(m1, m2)
  expect_gte(nrow(m1), 2L)
  for (i in seq_len(nrow(m1))) {
    f <- file.path(.ms_root, m1$rel[i])
    expect_true(file.exists(f), info = m1$rel[i])
    expect_identical(m1$sha256[i], .pe_disk_sha(f),
                     info = paste0("stamp off disk: ", m1$rel[i]))
    expect_identical(m1$rows[i],
                      as.character(length(readLines(f, warn = FALSE))))
    expect_true(nzchar(m1$campaign[i]))
  }
  hex <- strsplit("0123456789abcdef", "")[[1L]]
  expect_true(all(vapply(m1$sha256,
                         function(s) all(strsplit(s, "")[[1L]] %in% hex),
                         logical(1), USE.NAMES = FALSE)))
  cat("US-G2 PROVENANCE CENSUS: witnesses=", nrow(m1), " campaigns=",
      length(unique(m1$campaign)), " stamps-verified=", nrow(m1), "\n", sep = "")
})

test_that("US-G2 the scored sweep columns render live values from the committed CSV", {
  .pe_tool()
  e <- .pe_env()
  csv <- file.path(.ms_root, .pe_SWEEP_REL)
  sw <- e$spe_sweep(csv)
  for (col in .pe_SCORED) {
    expect_true(col %in% sw$names, info = paste0("scored column lost: ", col))
  }
  rendered <- e$spe_render(.ms_root)
  sp <- .pe_spans(paste0(rendered, collapse = "\n"))
  indep <- .pe_sweep_rows(readLines(csv, warn = FALSE))
  for (col in .pe_SCORED) {
    j <- which(indep$header == col)
    expect_length(j, 1L)
    want <- vapply(indep$rows, function(r) r[j], character(1), USE.NAMES = FALSE)
    got <- sp$value[sp$rel == .pe_SWEEP_REL & sp$col == col]
    expect_identical(got, want, info = paste0("column off witness: ", col))
    if (identical(col, "precision")) {
      expect_true(any(got != "0"), info = "precision renders only zeros (dead?)")
    }
  }
  cat("US-G2 SWEEP CENSUS: scored-cols=", length(.pe_SCORED), " rows=",
      length(indep$rows), " live=verified\n", sep = "")
})

test_that("US-G2 the built peer page (when the lane site is present) stays witness-only", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sd <- .pe_site_dir()
  if (is.na(sd)) skip("no lane-built site tree (R CMD check context)")
  page <- file.path(sd, "articles", "peer-evidence.html")
  if (!file.exists(page)) {
    stop("the lane-built site lacks articles/peer-evidence.html (US-G2 defect)")
  }
  a <- .pe_audit(readLines(page, warn = FALSE), .ms_root)
  expect_identical(a$violations, character(0),
                   info = paste0(a$violations, collapse = "\n"))
  expect_gte(a$spans, 8L)
  cat("US-G2 BUILT CENSUS: spans=", a$spans, " violations=0\n", sep = "")
})

# --- red halves: firing controls ------------------------------------------------------------

test_that("US-G2 a fabricated peer numeric and a mispointed witness pointer are named", {
  .pe_tool()
  e <- .pe_env()
  rendered <- e$spe_render(.ms_root)
  forged <- c(rendered,
    "<span class=\"peer-value\" data-col=\"fabricated\" data-witness=\"bench/results/does_not_exist_20260101T000000Z/witnesses/x.jsonl\">1.23</span>",
    "<span class=\"peer-value\" data-col=\"fabricated\" data-witness=\"bench/scenarios/out/compare_sweep.csv\">9.99999</span>")
  a <- .pe_audit(forged, .ms_root)
  expect_true(any(grepl("non-sanctioned witness", a$violations, fixed = TRUE)))
  expect_true(any(grepl("9.99999", a$violations, fixed = TRUE) &
                  grepl("off the witness bytes", a$violations, fixed = TRUE)))
  bytes <- paste0(readLines(file.path(.ms_root, "bench", "results",
    "bootstrap_vs_sigminer_20261013T175859Z", "witnesses", "arm_A1.jsonl"),
    warn = FALSE), collapse = "\n")
  hit <- .pe_gscan("\"wall\":", bytes)
  expect_false(is.null(hit))
  tail <- substr(bytes, hit$starts[1L] + hit$lens[1L], nchar(bytes))
  vend <- which(strsplit(tail, "")[[1L]] %in% c(",", "}"))
  expect_gte(length(vend), 1L)
  tok <- substr(tail, 1L, vend[1L] - 1L)
  expect_gte(nchar(tok), 2L)
  mis <- c(rendered, paste0("<span class=\"peer-value\" data-col=\"fabricated\" ",
                            "data-witness=\"", .pe_SWEEP_REL, "\">", tok,
                            "</span>"))
  a2 <- .pe_audit(mis, .ms_root)
  expect_true(any(grepl("off the witness bytes", a2$violations, fixed = TRUE) &
                  grepl(tok, a2$violations, fixed = TRUE)))
})

test_that("US-G2 the constructed-perfect sweep greens every scored column (dead-metric law)", {
  .pe_tool()
  e <- .pe_env()
  fake <- tempfile("pe-perfect-")
  dir.create(file.path(fake, "bench", "scenarios", "out"), recursive = TRUE)
  dir.create(file.path(fake, "bench", "results", "peer_control_campaign_T",
                        "witnesses"), recursive = TRUE)
  writeLines("{\"kind\":\"probe\",\"arm\":\"A1\",\"wall\":1.25,\"cpu\":1.25,\"rep\":1}",
             file.path(fake, "bench", "results", "peer_control_campaign_T",
                       "witnesses", "probe_A1_1.jsonl"))
  csv <- file.path(fake, "bench", "scenarios", "out", "compare_sweep.csv")
  writeLines(c("tau,tp,fp,fn,precision,recall,f1,split,merge",
               "0.5,5,0,0,1,1,1,0,0"), csv)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  sw <- e$spe_sweep(csv)
  expect_identical(sw$names, strsplit("tau,tp,fp,fn,precision,recall,f1,split,merge",
                                      ",", fixed = TRUE)[[1L]])
  sp <- .pe_spans(paste0(e$spe_render(fake), collapse = "\n"))
  for (col in .pe_SCORED) {
    got <- sp$value[sp$rel == .pe_SWEEP_REL & sp$col == col]
    perfect_value <- if (identical(col, "tau")) "0.5" else "1"
    expect_identical(got, perfect_value,
                     info = paste0("perfect control did not render perfect: ", col))
  }
  a <- .pe_audit(strsplit(paste0(e$spe_render(fake), collapse = "\n"),
                          "\n", fixed = TRUE)[[1L]], fake)
  expect_identical(a$violations, character(0),
                   info = paste0(a$violations, collapse = "\n"))
  expect_gte(a$spans, length(.pe_SCORED))
})

test_that("US-G2 a removed scored column reddens the tool, never a silent zero (firing)", {
  .pe_tool()
  e <- .pe_env()
  fake <- tempfile("pe-dead-")
  dir.create(fake, recursive = TRUE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base_cells <- strsplit("tau,tp,fp,fn,precision,recall,f1,split,merge", ",",
                         fixed = TRUE)[[1L]]
  for (col in .pe_SCORED) {
    keep <- vapply(base_cells, function(c0) !identical(c0, col), logical(1),
                   USE.NAMES = FALSE)
    csv <- file.path(fake, paste0("sweep_", col, ".csv"))
    writeLines(c(paste0(base_cells[keep], collapse = ","),
                 "0.7,5,0,0,1,1,1,0,0"), csv)
    err <- tryCatch({
      e$spe_sweep(csv)
      NA_character_
    }, error = function(cnd) conditionMessage(cnd))
    expect_true(is.character(err) && grepl("dead column", err, fixed = TRUE),
                info = paste0(col, ": the tool zero-filled a removed column"))
    expect_true(is.character(err) && grepl(col, err, fixed = TRUE),
                info = paste0(col, ": the refusal did not name the column"))
  }
})

test_that("US-G2 an empty sanctioned corpus is vacuous-red, never empty-green", {
  .pe_tool()
  fake <- tempfile("pe-empty-")
  dir.create(file.path(fake, "bench", "scenarios", "out"), recursive = TRUE)
  dir.create(file.path(fake, "bench", "results", "some_campaign", "notes"),
             recursive = TRUE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  a <- .pe_audit("<p>quiet page</p>", fake)
  expect_true(any(grepl("vacuous", a$violations, fixed = TRUE)))
  out <- tempfile("pe-empty-cli-")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  r <- .pe_cli(fake, out)
  expect_true(r$status != 0L, info = "the CLI accepted an empty peer corpus")
  expect_true(grepl("vacuous", r$out, fixed = TRUE))
})
