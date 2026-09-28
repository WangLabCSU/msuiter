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
quit(status = 0L)
