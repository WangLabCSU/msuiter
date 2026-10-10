#!/usr/bin/env Rscript
# docs-sync: API-surface consistency check (U-M0-05; ARCHITECTURE section 9
# "docs-sync 检查 ... drift 即红").
#
# Contract (docs/CAPABILITY-MATRIX.md, "矩阵治理"):
#   every user-facing `ms_*` API name that appears in ARCHITECTURE.md or
#   ROADMAP.md must be listed in the CAPABILITY-MATRIX "L-H API 表面" table.
#   FFI internals (`ms_tally_rust`, `ms_extract_rust`, i.e. any `ms_*_rust`
#   name, governed separately by docs/ffi-surface.md) are excluded.
#
# Any ARCH/ROADMAP user API missing from the L-H table is drift -> exit 1.
# The CI wiring lands in U-M0-07; this script is the check itself.
#
# Run:  Rscript tools/docs-sync.R          (exit 0 = in sync, exit 1 = drift)

options(warn = 1)

.repo_root <- local({
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) > 0L) dirname(dirname(normalizePath(f[1]))) else normalizePath(".")
})

.rd <- function(...) file.path(.repo_root, "docs", ...)

# Token regex: `ms_` preceded by a non-identifier character (so
# `register_ms_engine` does not match), lowercase snake_case body.
.token_regex <- "(?<![A-Za-z0-9_])ms_[a-z0-9_]+"

# FFI internals: governed by docs/ffi-surface.md, not user API promises.
.is_ffi_internal <- function(token) grepl("_rust$", token)

.extract_lh_table_apis <- function() {
  lines <- readLines(.rd("CAPABILITY-MATRIX.md"), warn = FALSE)
  start <- grep("^#{2,3} L-H API 表面", lines)
  if (length(start) != 1L) {
    stop("docs-sync: could not locate the L-H API surface table heading",
         call. = FALSE)
  }
  start <- start[1]
  # Table region ends at the next heading or horizontal rule.
  rest <- lines[(start + 1L):length(lines)]
  stop_at <- grep("^(#{1,3} |-{3,}\\s*$)", rest)
  stop_at <- if (length(stop_at)) min(stop_at) - 1L else length(rest)
  rows <- rest[seq_len(max(stop_at, 0L))]
  rows <- rows[startsWith(rows, "|")]
  tokens <- unlist(regmatches(rows, gregexpr(.token_regex, rows, perl = TRUE)),
                   use.names = FALSE)
  tokens <- unique(tokens[!.is_ffi_internal(tokens)])
  if (length(tokens) == 0L) {
    stop("docs-sync: L-H API surface table parsed to zero entries", call. = FALSE)
  }
  tokens
}

.extract_doc_apis <- function(file) {
  lines <- readLines(file, warn = FALSE)
  hits <- lapply(lines, function(l) {
    regmatches(l, gregexpr(.token_regex, l, perl = TRUE))[[1]]
  })
  data.frame(
    api = unlist(hits, use.names = FALSE),
    file = basename(file),
    line = rep(seq_along(lines), vapply(hits, length, integer(1))),
    stringsAsFactors = FALSE
  )
}

lh_apis <- .extract_lh_table_apis()
docs <- rbind(
  .extract_doc_apis(.rd("ARCHITECTURE.md")),
  .extract_doc_apis(.rd("ROADMAP.md"))
)
user <- docs[!.is_ffi_internal(docs$api), , drop = FALSE]

# FFI internals found in docs (informational: they must NOT be treated as
# user API commitments here).
ffi <- sort(unique(docs$api[.is_ffi_internal(docs$api)]))

drift <- setdiff(sort(unique(user$api)), lh_apis)

cat(sprintf(
  "docs-sync: L-H API surface entries: %d | user ms_* tokens in ARCHITECTURE/ROADMAP: %d\n",
  length(lh_apis), length(unique(user$api))
))
if (length(ffi)) {
  cat(sprintf("docs-sync: FFI internals excluded (docs/ffi-surface.md): %s\n",
              paste(ffi, collapse = ", ")))
}

if (length(drift)) {
  cat("docs-sync: DRIFT -- user APIs in ARCHITECTURE/ROADMAP missing from the",
      "CAPABILITY-MATRIX L-H API surface table:\n")
  for (api in drift) {
    where <- user[user$api == api, , drop = FALSE]
    for (k in seq_len(nrow(where))) {
      cat(sprintf("  %s  %s:%d\n", where$api[k], where$file[k], where$line[k]))
    }
  }
  cat("docs-sync: add these to the L-H API surface table (CAPABILITY-MATRIX.md)",
      "or fix the prose. Exiting 1.\n")
  quit(status = 1L)
}

cat("docs-sync: OK -- no API-surface drift\n")

# ---------------------------------------------------------------------------
# Half two: ROADMAP checkbox-truth (U-M7-04 slice-A; controller ruling
# 2026-10-10). A box flipped to [x] in the M6s / M7 / G sections is a
# completion claim, and a completion claim must be auditable: each such line
# must carry a parenthetical evidence citation containing a path:line
# reference or a commit-hash token (>= 7 hex chars).
# ---------------------------------------------------------------------------

.checkbox_line  <- "^\\s*- \\[[xX]\\]"
.section_head   <- "^#{2,4} "

# True iff some parenthetical segment of the line cites path:line or a commit.
# Capture-group extraction follows the proven house idiom (gregexec matcher,
# cf. test-channels-sync.R): regmatches rows are [full match, group 1...].
.checkbox_citation_ok <- function(line) {
  rl <- regmatches(line, gregexec("\\(([^()]*)\\)", line, perl = TRUE))
  if (!length(rl)) {
    return(FALSE)                       # no () group present at all
  }
  hits <- rl[[1]]
  segs <- hits[seq(2L, length(hits))]  # drop the full-match row, keep groups
  any(grepl("[A-Za-z0-9._/-]+\\.[A-Za-z0-9]+:[0-9]+", segs, perl = TRUE)) ||
  any(grepl("(?<![0-9a-f])[0-9a-f]{7,40}(?![0-9a-f])", segs, perl = TRUE))
}

.roadmap_checkbox_check <- function() {
  lines <- readLines(.rd("ROADMAP.md"), warn = FALSE)
  heads <- grep(.section_head, lines, perl = TRUE)
  if (!length(heads)) {
    stop("docs-sync: ROADMAP.md exposes no section headings", call. = FALSE)
  }
  section_of <- function(i) lines[max(heads[heads <= i])]
  in_scope   <- function(sec) grepl("M6s", sec) ||
                              grepl("M7\\b", sec, perl = TRUE) ||
                              grepl("G 门", sec, fixed = TRUE)
  checked <- grep(.checkbox_line, lines, perl = TRUE)
  bad <- character(0)
  n   <- 0L
  for (i in checked) {
    sec <- section_of(i)
    if (!in_scope(sec)) next
    n <- n + 1L
    if (!.checkbox_citation_ok(lines[i])) {
      bad <- c(bad, sprintf("ROADMAP.md:%d  %s", i,
                            substr(trimws(lines[i]), 1L, 96L)))
    }
  }
  list(n = n, bad = bad)
}

ct <- .roadmap_checkbox_check()
cat(sprintf("docs-sync: checkbox-truth: %d checked box(es) in M6s/M7/G sections\n",
            ct$n))
if (length(ct$bad)) {
  cat("docs-sync: checkbox-truth: DRIFT -- checked boxes without a",
      "parenthetical evidence citation (need path:line or commit token):\n")
  for (b in ct$bad) cat("  ", b, "\n", sep = "")
  cat("docs-sync: checkbox-truth: cite the committing evidence on these lines",
      "(or uncheck them). Exiting 1.\n")
  quit(status = 1L)
}
cat("docs-sync: checkbox-truth: OK -- every in-scope checked box cites its",
    "evidence\n")

# ---------------------------------------------------------------------------
# Half three: _pkgdown.yml reference-index completeness (U-M7-04 slice-C, C4).
# Contract (controller ruling 2026-10-10; docs/ARCHITECTURE.md section 9
# "docs-sync ... drift 即红", extended): every symbol NAMESPACE exports must
# appear in the _pkgdown.yml reference index -- pkgdown only publishes what
# the index names, so an unlisted export is an invisible API that no site
# build would ever flag. --namespace= / --pkgdown= override the targets so
# the red-state units in tests/testthat/test-docs-sync.R can point the
# checker at a tampered copy without touching committed files.
# ---------------------------------------------------------------------------

.pkgdown.args <- commandArgs(FALSE)
.pkgdown.arg <- function(key, default) {
  hit <- grep(paste0("^--", key, "="), .pkgdown.args)
  if (length(hit) == 0L) default else sub(paste0("^--", key, "="), "", .pkgdown.args[hit[1]])
}

.exported_symbols <- function(namespace) {
  lines <- readLines(namespace, warn = FALSE)
  tok <- sub("^export\\((.*)\\)$", "\\1", grep("^export\\(", lines, value = TRUE))
  if (length(tok) == 0L) {
    stop("docs-sync: NAMESPACE parsed to zero export() entries", call. = FALSE)
  }
  bad <- tok[!grepl("^[A-Za-z0-9._]+$", tok)]
  if (length(bad)) {
    stop(sprintf("docs-sync: unsupported export() form(s): %s",
                 paste(unique(bad), collapse = ", ")), call. = FALSE)
  }
  unique(tok)
}

.pkgdown_indexed <- function(yml) {
  lines <- readLines(yml, warn = FALSE)
  start <- grep("^reference:", lines)
  if (length(start) != 1L) {
    stop("docs-sync: _pkgdown.yml exposes no single reference: block", call. = FALSE)
  }
  rest <- lines[seq(start + 1L, length(lines))]
  stop_at <- grep("^[^[:space:]#-]", rest)   # next top-level key ends the block
  block <- if (length(stop_at)) rest[seq_len(min(stop_at) - 1L)] else rest
  tok <- trimws(sub("^[[:space:]]+-[[:space:]]+", "",
                    grep("^[[:space:]]+-[[:space:]]*[A-Za-z0-9._]+$", block, value = TRUE)))
  if (length(tok) == 0L) {
    stop("docs-sync: _pkgdown.yml reference index parsed to zero entries", call. = FALSE)
  }
  unique(tok)
}

.pkgdown_ns <- .pkgdown.arg("namespace", file.path(.repo_root, "NAMESPACE"))
.pkgdown_yml <- .pkgdown.arg("pkgdown", file.path(.repo_root, "_pkgdown.yml"))
exports <- .exported_symbols(.pkgdown_ns)
indexed <- .pkgdown_indexed(.pkgdown_yml)
missing <- setdiff(exports, indexed)
ghost   <- setdiff(indexed, exports)
if (length(ghost)) {
  # An indexed name with no export is tolerated only if it is really
  # documented (man/<name>.Rd) -- otherwise the site build would die on it.
  ghost <- ghost[!file.exists(file.path(.repo_root, "man", paste0(ghost, ".Rd")))]
}

cat(sprintf("docs-sync: pkgdown-index: %d NAMESPACE export(s), %d index entries\n",
            length(exports), length(indexed)))
if (length(missing) || length(ghost)) {
  cat("docs-sync: pkgdown-index: DRIFT -- the _pkgdown.yml reference index and NAMESPACE disagree:\n")
  for (t in missing) cat(sprintf("  export missing from the index: %s\n", t))
  for (t in ghost) cat(sprintf("  index entry with no export and no man/%s.Rd: %s\n", t, t))
  cat("docs-sync: pkgdown-index: add the exports to the reference index",
      "(_pkgdown.yml) or fix the ghost entries. Exiting 1.\n")
  quit(status = 1L)
}
cat(sprintf("docs-sync: pkgdown-index: OK -- all %d exported symbol(s) carry a reference-index entry\n",
            length(exports)))

quit(status = 0L)
