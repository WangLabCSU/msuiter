#!/usr/bin/env Rscript
# cjk-census: English-only compliance census over the normative doc corpus
# (docs audit 2026-10-13, F-01; translation-law gates of the corpus pass).
#
# Contract (the English-only law + the corpus-pass translation law):
#   * "normative" corpus files must carry CJK codepoints only inside
#     blockquote (">") and fenced-code (```/~~~) contexts -- those regions
#     are frozen verbatim ruling/evidence text and byte-frozen code, kept as
#     the authoritative original (translation law rules 2 and 3). Any CJK
#     line outside those regions is drift -> exit 1.
#   * "bilingual" files carry a HISTORICAL SNAPSHOT stamp and keep their
#     Chinese originals byte-identical under prepended English renderings:
#     exempt by design. The census reports their counts and flags REVIEW;
#     the controller reviews, the gate does not fail.
#   * "reference" rows are informational context only, never gated.
#
# Numeric-preservation guard (translation law rule 3): against a baseline git
# rev, every digit-run token of the baseline blob must survive into the
# working file with at least the same multiplicity. Losing a numeric claim in
# a translation is drift -> exit 1.
#
# Run:  Rscript tools/cjk-census.R [--baseline=REF] [--quiet]
#       (exit 0 = compliant, exit 1 = violations; default REF = HEAD)

options(warn = 1)

.repo_root <- local({
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f) > 0L) {
    dirname(dirname(normalizePath(f[1])))
  } else {
    normalizePath(".")
  }
})

.args <- local({
  a <- commandArgs(FALSE)
  a[!grepl("^--file=", a)]
})

.get_opt <- function(flag, default) {
  hit <- grepl(paste0("^", flag, "="), .args)
  if (!any(hit)) return(default)
  sub(paste0("^", flag, "="), "", .args[hit][1])
}

.baseline <- .get_opt("--baseline", "HEAD")
.quiet    <- "--quiet" %in% .args

# CJK class: Han ideographs (incl. ext-a), Japanese syllabaries, Hangul,
# CJK punctuation and the fullwidth/halfwidth block. Written with \p{} and
# \x{} escapes so this file stays pure ASCII (English-only law).
.cjk_regex <- paste0(
  "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}",
  "\\x{3000}-\\x{303f}\\x{3040}-\\x{30ff}",
  "\\x{ff00}-\\x{ffef}]"
)

# Corpus roster: path -> compliance class.
.corpus <- c(
  "docs/ROADMAP.md"                              = "normative",
  "docs/ARCHITECTURE.md"                          = "normative",
  "docs/CAPABILITY-MATRIX.md"                     = "normative",
  "docs/IMPLEMENTATION-PLAN.md"                   = "normative",
  "docs/PERFORMANCE.md"                           = "normative",
  "docs/ffi-surface.md"                           = "normative",
  "CONTRIBUTING.md"                               = "normative",
  "NEWS.md"                                      = "normative",
  "docs/research/00-executive-summary.md"         = "normative",
  "docs/research/01-extraction-methods.md"        = "normative",
  "docs/research/02-fitting-inference.md"         = "normative",
  "docs/research/03-applications.md"              = "normative",
  "docs/research/04-source-audit.md"              = "normative",
  "docs/research/05-standards-data.md"            = "normative",
  "docs/research/06-s7-class-system.md"           = "normative",
  "docs/research/07-algorithm-zoo.md"             = "normative",
  "docs/research/08-fact-check-audit.md"          = "normative",
  "docs/reviews/00-synthesis.md"                  = "normative",
  "docs/reviews/01-computational-biologist.md"    = "normative",
  "docs/reviews/02-rust-r-engineer.md"            = "normative",
  "docs/reviews/03-ml-statistician.md"            = "normative",
  "docs/reviews/04-software-engineer.md"          = "normative",
  "docs/reviews/05-nature-editor.md"              = "normative",
  "docs/adr/0001-twobit-reader-choice.md"         = "normative",
  "docs/adr/0002-vendor-budget.md"                = "normative",
  "bench/g0/README.md"                            = "normative",
  "bench/g0/adapters/adapter_protocol.md"         = "normative",
  "bench/m1s/README.md"                           = "normative",
  "bench/m1s/result.md"                           = "normative",
  "_pkgdown.yml"                                 = "normative",
  "man/ms_fit.Rd"                                 = "normative",
  "man/ms_calibration_sanity.Rd"                  = "normative",
  "docs/release/v0.1-checklist.md"                = "bilingual",
  "bench/m1s/nmf/result.md"                       = "reference",
  "bench/m1s/nnls/result.md"                      = "reference",
  "bench/m1s/sbs/result.md"                       = "reference"
)

# Per-line markdown context: TRUE where CJK is permitted to survive
# (blockquote or fenced code).
.context_flags <- function(lines) {
  n <- length(lines)
  quote <- logical(n)
  fence <- logical(n)
  open <- FALSE
  fence_re <- "^\\s*(```+|~{3,})"
  for (i in seq_len(n)) {
    if (grepl(fence_re, lines[i], perl = TRUE)) {
      fence[i] <- TRUE          # the fence line itself is code context
      open <- !open
      next
    }
    fence[i] <- open
    quote[i] <- grepl("^\\s*>", lines[i], perl = TRUE)
  }
  list(quote = quote, fence = fence)
}

# R's PCRE wrapper picks the Oniguruma encoding from the SUBJECT strings: an
# all-ASCII line vector compiles the pattern in ASCII mode, where the
# \x{3000}-class escapes above are rejected as "code point value too large".
# A fully translated (ASCII) corpus file would then abort the census. Tag the
# read lines as UTF-8 so the pattern always compiles in UTF-8 mode.
.force_utf8 <- function(x) {
  Encoding(x) <- "UTF-8"
  x
}

# grep() consults the encoding of each subject element; copying a pure-ASCII
# line back out of a UTF-8-tagged vector drops the tag again. Appending one
# known UTF-8 element per call forces UTF-8 compilation for the whole batch;
# the sentinel index (always FALSE, unassigned codepoint) is discarded.
.SENTINEL <- "\u{ffff}"
.cjk_hit <- function(x) {
  hits <- grep(.cjk_regex, c(x, .SENTINEL), perl = TRUE)
  seq_along(x) %in% hits
}

.read_work <- function(relpath) {
  p <- file.path(.repo_root, relpath)
  if (!file.exists(p)) return(NULL)
  lines <- readLines(p, warn = FALSE, encoding = "UTF-8")
  .force_utf8(lines)
}

.read_baseline <- function(relpath, rev) {
  of <- tempfile()
  ef <- tempfile()
  rc <- tryCatch(system2("git", c("show", paste0(rev, ":", relpath)),
                         stdout = of, stderr = ef),
                 error = function(e) 1L)
  if (!identical(rc, 0L) || !file.exists(of)) return(NULL)
  .force_utf8(readLines(of, warn = FALSE, encoding = "UTF-8"))
}

.digit_tokens <- function(lines) {
  unlist(regmatches(lines, gregexpr("[0-9]+", lines, perl = TRUE)),
          use.names = FALSE)
}

# In-file, auditable exemption directives (they ride with the reviewed diff):
#   <!-- census-exempt digests: <64-hex> ... -->  bounded waiver: for every
#     named hex digest one occurrence of each of its digit-run tokens is
#     removed from the baseline multiset -- for deliberately re-pinned
#     derived artifacts (integrity seals re-secured to a translated blob).
#   <!-- census-exempt tokens: <tok> ... -->      token waiver: the named
#     tokens are exempted from the loss check -- for deliberately moved
#     derived pointers (line pins re-anchored after the line-number shift).
# Both carry their reason in the comment prose; a body numeric claim cannot
# silently disappear without a visible directive in the file diff.
.cjk_exempt <- function(lines) {
  txt <- paste0(lines, collapse = "\n")
  bodies <- function(kind) {
    ms <- gregexpr(paste0("<!-- census-exempt ", kind, ": [^>]*-->"), txt,
                   perl = TRUE)[[1]]
    ml <- attr(ms, "match.length")
    ok <- !is.na(ms) && ms > 0L
    if (!any(ok)) return(character(0))
    vapply(which(ok), function(r) {
      z <- substring(txt, ms[r], ms[r] + ml[r] - 1L)
      z <- sub(paste0("<!-- census-exempt ", kind, ": "), "", z, fixed = TRUE)
      sub(" *-->$", "", z)
    }, character(1L))
  }
  words <- function(zs) {
    w <- unlist(lapply(zs, function(z) strsplit(z, "[ ]+")[[1]]))
    w <- w[nzchar(w)]
    if (length(w) == 0L) character(0) else w
  }
  digests <- words(bodies("digests"))
  digests <- digests[grepl("^[0-9a-fA-F]{64}$", digests)]
  list(digests = digests, tokens = words(bodies("tokens")))
}

# ---------------------------------------------------------------------------
violations <- character(0)
lost_rows  <- character(0)
rows       <- list()

for (relpath in names(.corpus)) {
  cls   <- unname(.corpus[[relpath]])
  lines <- .read_work(relpath)
  if (is.null(lines)) {
    rows[[relpath]] <- list(cls = cls, total = NA_integer_, base = NA_integer_,
                            now = NA_integer_, exposed = NA_integer_,
                            status = "MISSING (no working-tree file)")
    if (cls == "normative") {
      violations <- c(violations, paste0(relpath, ": missing from the working tree"))
    }
    next
  }
  ctx     <- .context_flags(lines)
  is_cjk  <- .cjk_hit(lines)
  exposed <- sum(is_cjk & !(ctx$quote | ctx$fence))
  base    <- NA_integer_
  if (!is.na(.baseline) && nzchar(.baseline) && cls %in% c("normative", "bilingual")) {
    bl <- .read_baseline(relpath, .baseline)
    if (!is.null(bl)) {
      base <- sum(.cjk_hit(bl))
      tb <- table(.digit_tokens(bl))
      ex <- .cjk_exempt(lines)
      for (d in ex$digests) for (r in .digit_tokens(d)) {
        if (!is.na(tb[[r]]) && tb[[r]] > 0L) tb[[r]] <- tb[[r]] - 1L
      }
      for (t0 in ex$tokens) tb[t0] <- 0L
      tb <- tb[tb > 0L]
      tc <- table(.digit_tokens(lines))
      lost <- character(0)
      for (tk in names(tb)) {
        have <- if (tk %in% names(tc)) tc[[tk]] else 0L
        if (have < tb[[tk]]) {
          lost <- c(lost, sprintf("%s(x%d>have%d)", tk, tb[[tk]], have))
        }
      }
      if (length(lost)) {
        lost_rows <- c(lost_rows,
          sprintf("%s: baseline digit-run token(s) lost vs %s: %s",
                  relpath, .baseline, paste0(lost, collapse = ", ")))
      }
    }
  }
  status <- switch(cls,
    normative = if (exposed > 0L) {
                  sprintf("VIOLATION (%d CJK line(s) outside quote/code)", exposed)
                } else if (sum(is_cjk) > 0L) {
                  sprintf("OK (all %d CJK line(s) quote/fence-preserved)", sum(is_cjk))
                } else "OK",
    bilingual = sprintf("REVIEW (bilingual by design; %d CJK line(s) preserved)",
                        sum(is_cjk)),
    reference = "report only")
  rows[[relpath]] <- list(cls = cls, total = length(lines), base = base,
                          now = sum(is_cjk), exposed = exposed, status = status)
  if (cls == "normative" && exposed > 0L) {
    at <- which(is_cjk & !(ctx$quote | ctx$fence))
    preview <- head(sprintf("%s:%d", relpath, at), 8L)
    violations <- c(violations,
      sprintf("%s: %d CJK line(s) outside quote/code context (first lines: %s%s)",
              relpath, exposed, paste0(preview, collapse = ", "),
              if (exposed > 8L) ", ..." else ""))
  }
}

# ---------------------------------------------------------------------------
if (!.quiet) {
  cat(sprintf("%-48s %-9s %6s %8s %7s  %s\n",
              "file", "class", "lines", "CJK-base", "CJK-now", "status"))
  for (relpath in names(.corpus)) {
    r <- rows[[relpath]]
    cat(sprintf("%-48s %-9s %6s %8s %7s  %s\n",
                relpath, r$cls,
                if (is.na(r$total)) "-" else format(r$total),
                if (is.na(r$base)) "-" else format(r$base),
                if (is.na(r$now)) "-" else format(r$now),
                r$status))
  }
}

norm_exposed <- 0L
for (r in rows) {
  if (r$cls == "normative" && !is.na(r$exposed)) {
    norm_exposed <- norm_exposed + r$exposed
  }
}
cat(sprintf("\ncjk-census: %d file(s) censused; baseline rev = %s\n",
            length(.corpus), .baseline))
cat(sprintf("cjk-census: normative CJK outside quote/code context: %d line(s)\n",
            norm_exposed))

if (length(lost_rows)) {
  for (m in lost_rows) cat("NUMERIC-DROP  ", m, "\n")
}
if (length(violations)) {
  for (v in violations) cat("VIOLATION  ", v, "\n")
}
if (length(lost_rows) || length(violations)) {
  cat("cjk-census: FAIL\n")
  quit(status = 1L)
}
cat("cjk-census: OK\n")
quit(status = 0L)
