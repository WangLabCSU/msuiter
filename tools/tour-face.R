# tour-face.R -- DS-4 US-H1 tour-page executable-promise instrument (docs/site v4).
# The law (tests/testthat/test-docs-tour-executable.R) owns the expectations;
# this file is the single re-derivation face: it parses the Rmd code chunks,
# evaluates the R face in-process in a sandbox over the msuiter namespace
# (the page's own dual-load posture pinned to the reader-side branch, so a
# check-time tree can never trigger a pkgload rebuild of the source tree),
# snapshots the written fixture genome before the page's cleanup chunk
# unlinks it, reads the 2bit bytes back independently, and re-derives every
# prose numeral from the live face: channel count, base-level trinucleotide
# context, input/record/ledger counts, SNV/sample counts, the genome strings,
# the committed byte geometry and the error-surface classes. Fail-closed
# everywhere: a zero-chunk parse, a missing chunk, a missing claim anchor or
# an unreachable helper writer is a stop, never an empty pass. No hand-typed
# numerics: prose tokens and the fixture chunk's own declared constants are
# the inputs; the evaluated face and the disk bytes are the ground.
# Dialect: this base's regexec/regmatches fault on capture extraction (measured
# 2026-11-02), so all capture work rides grep/grepl plus sub backreferences.
# usage: Rscript tools/tour-face.R [--root=<dir>] [--page=<path>]

.tf_stop <- function(msg) stop(msg, domain = NA, call. = FALSE)

.tf_args <- local({
  ca <- try(commandArgs(trailingOnly = TRUE), silent = TRUE)
  if (inherits(ca, "try-error")) ca <- character()
  as.character(ca[nzchar(as.character(ca))])
})
.tf_get <- function(flag, default = "") {
  hit <- grepl(paste0("^--", flag, "="), .tf_args)
  if (!any(hit)) return(default)
  sub(paste0("^--", flag, "="), "", .tf_args[which(hit)[1L]])
}

.tf_root <- function() {
  r <- .tf_get("root")
  if (nzchar(r)) return(normalizePath(r))
  p <- normalizePath(getwd())
  repeat {
    if (file.exists(file.path(p, "DESCRIPTION"))) return(p)
    up <- dirname(p)
    if (identical(up, p)) .tf_stop("vacuous: no package root above the working directory")
    p <- up
  }
}

.tf_trim <- function(x) gsub("^[[:space:]]+|[[:space:]]+$", "", x)

# sub-backreference capture arms (this base's regex capture fault workaround;
# the backreference token is built from intToUtf8(92) so no source-escape
# layer can mangle it -- measured 2026-11-02 on this base's parser). The
# pattern must cover the whole string (callers own their .* framing);
# the result is the bare capture group.
.tf_cap <- function(pat, x, n = 1L) {
  if (!length(x) || !grepl(pat, x)) return(NA_character_)
  if (n < 1L || n > 4L) .tf_stop("capture arms beyond four are not provided")
  # an arm the pattern never opened would make sub read the token as an
  # octal escape; ask for nothing the pattern cannot give
  ngrp <- nchar(gsub("[^\\(]", "", pat))
  if (n > ngrp) return(NA_character_)
  v <- sub(paste0("^", pat, "$"), paste0(intToUtf8(92L), as.character(n)), x)
  if (identical(v, x)) NA_character_ else v
}

# --- chunk face ------------------------------------------------------------------------

.tf_wordnum <- c(one = 1L, two = 2L, three = 3L, four = 4L, five = 5L, six = 6L,
                 seven = 7L, eight = 8L, nine = 9L, ten = 10L, eleven = 11L,
                 twelve = 12L)

.tf_numword <- function(w) {
  v <- .tf_wordnum[[tolower(w)]]
  if (is.null(v)) NA_integer_ else as.integer(v)
}

# Parse the fenced Rmd into data.frame(name, lang, eval, start, end, body).
# Fail-closed: zero R chunks is vacuous (the law forbids empty-green parses).
tf_chunks <- function(rmd) {
  if (!file.exists(rmd)) .tf_stop(paste0("Rmd not on disk: ", rmd))
  lines <- readLines(rmd, warn = FALSE)
  fence <- grep("^```", lines)
  name <- character(0); lang <- character(0); evals <- logical(0)
  start <- integer(0); end <- integer(0); body <- list()
  k <- 1L
  while (k <= length(fence)) {
    open <- fence[k]
    close <- if (k + 1L <= length(fence)) fence[k + 1L] else length(lines) + 1L
    hdr <- .tf_trim(sub("[}]$", "", sub("^```[{]", "", lines[open])))
    toks <- lapply(strsplit(hdr, ",")[[1L]], .tf_trim)
    # the language token may carry a trailing chunk label: "{r setup, opts}"
    first <- strsplit(toks[[1L]], "[[:space:]]+")[[1L]]
    lg <- first[1L]
    lb <- if (length(first) > 1L) first[2L] else ""
    if (!nzchar(lb) && length(toks) > 1L &&
        !grepl("=", toks[[2L]], fixed = TRUE)) lb <- toks[[2L]]
    body[[length(body) + 1L]] <-
      if (close - 1L > open) lines[(open + 1L):(close - 1L)] else character(0)
    name <- c(name, lb); lang <- c(lang, lg); evals <- c(evals,
      !grepl("eval[[:space:]]*=[[:space:]]*FALSE", hdr))
    start <- c(start, open); end <- c(end, close)
    k <- k + 2L
  }
  out <- data.frame(name = name, lang = lang, eval = evals,
                    start = start, end = end, stringsAsFactors = FALSE)
  out$body <- body
  if (!length(name) || !sum(lang == "r")) {
    .tf_stop(paste0("vacuous: zero R chunks in ", rmd))
  }
  out
}

.tf_require_chunk <- function(chunks, name) {
  if (!name %in% chunks$name) .tf_stop(paste0("chunk missing: ", name))
  which(chunks$name == name)[1L]
}

# --- claim face ------------------------------------------------------------------------

.tf_needed_chunks <- c("setup", "fixture", "variants", "tally", "signature", "errors")

# Canonical prose anchors. Every claim the tour page makes about the embedded
# face must still be present and speakable; a vanished or duplicated anchor is
# a stop (claim amputation is RED, not an empty pass). t1..t3 carry the
# capture groups. The trinucleotide pattern mirrors no backreference (this
# base's engine speaks none): the right flank is captured openly and its
# equality to the left flank is proven against the written bytes downstream.
tf_claims <- function(rmd) {
  chunks <- tf_chunks(rmd)
  for (nm in .tf_needed_chunks) .tf_require_chunk(chunks, nm)
  lines <- readLines(rmd, warn = FALSE)
  fence <- grep("^```", lines)
  prose <- rep(TRUE, length(lines))
  k <- 1L
  while (k <= length(fence)) {
    a <- fence[k]; b <- if (k + 1L <= length(fence)) fence[k + 1L] else length(lines)
    prose[a:b] <- FALSE; k <- k + 2L
  }
  if (!sum(prose)) .tf_stop(paste0("vacuous: zero prose lines in ", rmd))
  plines <- which(prose)
  claim <- character(0); line <- integer(0)
  t1 <- character(0); t2 <- character(0); t3 <- character(0); t4 <- character(0)
  drift <- character(0)
  add <- function(nm, pat) {
    hit <- grep(pat, lines[prose])
    if (!length(hit)) drift <<- c(drift, paste0("claim anchor missing: ", nm))
    if (length(hit) > 1L) drift <<- c(drift, paste0("claim anchor duplicated: ", nm))
    if (length(hit) == 1L) {
      ln <- plines[hit]
      x <- lines[ln]
      claim <<- c(claim, nm); line <<- c(line, ln)
      full <- paste0(".*", pat, ".*")
      cap <- function(k) {
        w <- .tf_cap(full, x, k)
        if (identical(w, x)) "" else w
      }
      t1 <<- c(t1, cap(1L)); t2 <<- c(t2, cap(2L))
      t3 <<- c(t3, cap(3L)); t4 <<- c(t4, cap(4L))
    }
  }
  add("channel-count",       "one of the ([0-9]{2,3}) SBS channels")
  add("variant-position",    "at `([A-Za-z0-9]+):([0-9]+)`")
  add("trinuc-context",      "([ACGT])\\[([ACGT])>([ACGT])\\]([ACGT])")
  add("record-drop",         "([A-Z][a-z]+) of the ([a-z]+) data lines become records")
  add("skip-ledger",         "ledger entries `([a-z_]+)` and `([a-z_]+)`")
  add("snv-sample-count",    "([A-Z][a-z]+) SNVs in ([a-z]+) samples")
  add("genome-pattern-chr1", "`chr1` = `([ACGT]{4})[^`]`")
  add("genome-pattern-chr2", "`chr2` = `([ACGT]{4})[^`]`")
  add("writer-identity",     "same little-endian writer the test-suite helpers use")
  add("error-surface",       "`msuiter_error_\\*`")
  if (length(drift)) .tf_stop(paste0(drift, collapse = "; "))
  out <- data.frame(claim = claim, line = line, t1 = t1, t2 = t2, t3 = t3,
                    t4 = t4, stringsAsFactors = FALSE)
  out
}

# --- fixture-code params -----------------------------------------------------------------

# Read the geometry the fixture chunk itself declares (size/nb/nl per record):
# the face's own code is the witness for the byte-level checks, never a
# hand-typed constant inside this instrument.
tf_fixture_params <- function(rmd, chunks) {
  i <- .tf_require_chunk(chunks, "fixture")
  txt <- paste0(chunks$body[[i]], collapse = "\n")
  pieces <- strsplit(txt, "list\\(name[[:space:]]*=[[:space:]]*")[[1L]]
  if (length(pieces) != 3L) .tf_stop("fixture chunk lost its two-record shape")
  nm <- vapply(pieces[-1L], function(p) .tf_cap("\"([A-Za-z0-9]+)\".*", p),
               character(1), USE.NAMES = FALSE)
  sz <- vapply(pieces[-1L], function(p)
    as.integer(.tf_cap(".*size[[:space:]]*=[[:space:]]*([0-9]+)L.*", p)), integer(1),
    USE.NAMES = FALSE)
  num <- function(p, key) {
    if (grepl(paste0(key, "[[:space:]]*=[[:space:]]*integer\\(0\\)"), p)) {
      return(NA_integer_)
    }
    as.integer(.tf_cap(paste0(".*", key, "[[:space:]]*=[[:space:]]*([0-9]+)L.*"), p))
  }
  nb <- vapply(pieces[-1L], function(p) num(p, "nb"), integer(1), USE.NAMES = FALSE)
  nl <- vapply(pieces[-1L], function(p) num(p, "nl"), integer(1), USE.NAMES = FALSE)
  if (any(is.na(sz)) || any(is.na(nm)) || !all(nm %in% c("chr1", "chr2"))) {
    .tf_stop("fixture chunk record declarations unreadable")
  }
  # The N-block mask the fixture writes (`chr1[51L:53L] <- 0L`): the prose
  # alternation claim is read against the bytes OUTSIDE this window; inside
  # it the packed zero value (T) is what the bytes must carry.
  lo <- as.integer(.tf_cap(".*chr1\\[([0-9]+)L:.*", txt))
  hi <- as.integer(.tf_cap(".*chr1\\[[0-9]+L:([0-9]+)L\\].*", txt))
  nmask <- if (is.na(lo) || is.na(hi)) integer(0) else lo:hi
  list(recs = data.frame(name = nm, size = sz, nb = nb, nl = nl,
                         stringsAsFactors = FALSE),
       nmask = nmask)
}

# --- 2bit byte face (independent reader; never reuses the writer) --------------------------

.tf_read2bit_int <- function(bytes, p0) {
  # little-endian u32 at 0-based byte offset p0
  v <- as.integer(bytes[(p0 + 1L):(p0 + 4L)])
  v[1L] + v[2L] * 256L + v[3L] * 65536L + v[4L] * 16777216L
}

tf_read2bit <- function(path) {
  if (!file.exists(path)) .tf_stop(paste0("fixture genome not on disk: ", path))
  # this base's readBin rejects n = Inf -- size the read from the file
  bytes <- readBin(file(path, "rb"), what = raw(), n = as.integer(file.size(path)))
  n <- length(bytes)
  if (n < 16L) .tf_stop("2bit file truncated below its header")
  magic <- sprintf("0x%08X", .tf_read2bit_int(bytes, 0L))
  nrec <- .tf_read2bit_int(bytes, 8L)
  p <- 16L
  iname <- character(0); ioff <- integer(0)
  for (k in seq_len(nrec)) {
    ln <- as.integer(bytes[p + 1L])
    iname <- c(iname, rawToChar(bytes[(p + 2L):(p + 1L + ln)]))
    ioff <- c(ioff, .tf_read2bit_int(bytes, p + 1L + ln))
    p <- p + 1L + ln + 4L
  }
  ends <- c(ioff[-1L], n)  # 0-based start of the next record == end of this one
  rec <- lapply(seq_len(nrec), function(k) bytes[(ioff[k] + 1L):ends[k]])
  list(bytes = bytes, magic = magic, nrec = nrec,
       index = data.frame(name = iname, off = ioff, stringsAsFactors = FALSE),
       rec_bytes = rec, file_size = n)
}

# 2bit unpack: T=0 C=1 A=2 G=3, first base in the high bits.
tf_unpack <- function(dna, n) {
  out <- character(0)
  for (b in as.integer(dna)) {
    for (s in c(6L, 4L, 2L, 0L)) {
      out <- c(out, c("T", "C", "A", "G")[[bitwAnd(bitwShiftR(b, s), 3L) + 1L]])
    }
  }
  out[seq_len(n)]
}

# record header length under the shared writer's dialect: a u32 is emitted
# only when its field carries a value (writeBin of an empty integer writes no
# bytes), so empty-nb/empty-nl records are shorter -- re-derived, never
# hard-typed: size, nb-count, [nb], [nl], two reserved zeros.
.tf_rec_header <- function(nb, nl) {
  # size + nb-count always; the nb/nl value u32s ride only when the fixture
  # declared a value (empty writeBin drops its bytes); two reserved zeros close
  h <- 8L
  if (!is.na(nb)) h <- h + 4L
  if (!is.na(nl)) h <- h + 4L
  h + 8L
}

# --- in-process sandbox ---------------------------------------------------------------------

tf_sandbox <- function(rmd, root) {
  if (!requireNamespace("msuiter", quietly = TRUE)) {
    .tf_stop("msuiter namespace unavailable for the in-process face evaluation")
  }
  if (!requireNamespace("knitr", quietly = TRUE)) {
    .tf_stop("knitr namespace unavailable for the in-process face evaluation")
  }
  chunks <- tf_chunks(rmd)
  .tf_require_chunk(chunks, "setup")
  env <- new.env(parent = asNamespace("msuiter"))
  # The dual-load plumbing is environment, not promise: pin the setup chunk to
  # its reader-side branch so a check-time tree can never trigger a pkgload
  # rebuild of the source tree.
  assign("requireNamespace",
         function(package, ...) if (identical(package, "pkgload")) FALSE
         else base::requireNamespace(package, ...), envir = env)
  out <- list()
  snap <- NA_character_
  for (i in seq_len(nrow(chunks))) {
    if (chunks$lang[i] != "r" || !chunks$eval[i]) next
    exprs <- parse(text = paste0(chunks$body[[i]], collapse = "\n"))
    buf <- character(0)
    for (e1 in exprs) {
      buf <- c(buf, as.character(capture.output(eval(e1, envir = env))))
    }
    out[[length(out) + 1L]] <- buf
    names(out)[length(out)] <- chunks$name[i]
    if (chunks$name[i] == "fixture") {
      if (!exists("genome", envir = env, inherits = FALSE)) {
        .tf_stop("fixture chunk produced no 'genome' path to snapshot")
      }
      src <- get("genome", envir = env)
      if (!file.exists(src)) .tf_stop("fixture genome vanished before snapshot")
      snap <- tempfile("tour-face-genome-")
      if (!file.copy(src, snap)) .tf_stop("fixture genome snapshot failed")
    }
  }
  list(env = env, out = out, genome_snapshot = snap, root = root)
}

# --- audit ------------------------------------------------------------------------------------

tf_audit <- function(rmd, sb, par) {
  claims <- tf_claims(rmd)
  v <- character(0)
  n_checked <- 0L
  at <- function(nm) {
    i <- which(claims$claim == nm)
    if (length(i) != 1L) .tf_stop(paste0("claim lost mid-audit: ", nm))
    i
  }
  tok <- function(nm, k = 1L) claims[[paste0("t", k)]][at(nm)]
  ev1 <- function(expr) eval(parse(text = expr)[[1L]], envir = sb$env)
  want <- function(nm, k, got, word = FALSE) {
    gotc <- as.character(got)
    wantc <- tok(nm, k)
    if (word) wantc <- as.character(.tf_numword(wantc))
    if (!identical(gotc, wantc)) {
      v <<- c(v, paste0(nm, ": prose says ", wantc, ", face re-derives ",
                        gotc, " (line ", claims$line[at(nm)], ")"))
    }
    n_checked <<- n_checked + 1L
  }
  want("channel-count", 1L, ev1("nrow(cat1@counts)"))
  if (!identical(as.character(ev1("length(cat1@channels$labels)")), tok("channel-count"))) {
    v <- c(v, "channel-count: labels off the counts shape")
  }
  n_checked <- n_checked + 1L
  want("record-drop", 1L, ev1("v@provenance$parse$n_records"), word = TRUE)
  want("record-drop", 2L, ev1("v@provenance$parse$n_lines"), word = TRUE)
  want("snv-sample-count", 1L, ev1("nrow(tab)"), word = TRUE)
  want("snv-sample-count", 2L, ev1("length(unique(tab$sample))"), word = TRUE)
  led <- names(ev1("v@provenance$parse$skip_reasons"))
  for (k in c(1L, 2L)) {
    if (!(tok("skip-ledger", k) %in% led)) {
      v <- c(v, paste0("skip-ledger: prose names ", tok("skip-ledger", k),
                       ", face ledger carries [", paste0(led, collapse = ", "), "]"))
    }
    n_checked <- n_checked + 1L
  }
  # base-level and byte-level truth, read back from disk -- not from the writer
  g <- tf_read2bit(sb$genome_snapshot)
  if (!identical(g$magic, "0x1A412743")) v <- c(v, paste0("geometry: magic off (", g$magic, ")"))
  if (!identical(g$nrec, nrow(par$recs))) v <- c(v, paste0("geometry: nrec ", g$nrec))
  idx_len <- sum(1L + nchar(g$index$name) + 4L)
  if (!identical(g$index$off[1L], 16L + idx_len)) {
    v <- c(v, "geometry: first offset off the index walk")
  }
  for (k in seq_len(g$nrec)) {
    hd <- .tf_rec_header(par$recs$nb[k], par$recs$nl[k])
    dnalen <- as.integer(ceiling(par$recs$size[k] / 4L))
    if (!identical(length(g$rec_bytes[[k]]), hd + dnalen)) {
      v <- c(v, paste0("geometry: record ", par$recs$name[k], " length off the declared shape"))
    }
    if (!identical(.tf_read2bit_int(g$rec_bytes[[k]], 0L), par$recs$size[k])) {
      v <- c(v, paste0("geometry: record ", par$recs$name[k], " size field off the declared size"))
    }
    n_checked <- n_checked + 2L
  }
  if (!identical(g$file_size,
                  g$index$off[g$nrec] + length(g$rec_bytes[[g$nrec]]))) {
    v <- c(v, "geometry: file size off the record walk")
  }
  n_checked <- n_checked + 1L
  # the written bytes must carry the face's declared N-block/n-lane claims
  # verbatim: size u32, nb-count u32, [nb] u32, [nl] u32, two reserved zeros
  nb_off <- 8L
  if (!is.na(par$recs$nb[1L])) {
    if (!identical(.tf_read2bit_int(g$rec_bytes[[1L]], nb_off), par$recs$nb[1L])) {
      v <- c(v, "geometry: N-block record field off the fixture declaration")
    }
    n_checked <- n_checked + 1L
    nb_off <- nb_off + 4L
  }
  if (!is.na(par$recs$nl[1L])) {
    if (!identical(.tf_read2bit_int(g$rec_bytes[[1L]], nb_off), par$recs$nl[1L])) {
      v <- c(v, "geometry: n-lane record field off the fixture declaration")
    }
    n_checked <- n_checked + 1L
  }
  chrom <- tok("variant-position", 1L)
  pos <- as.integer(tok("variant-position", 2L))
  if (!identical(g$index$name[1L], chrom)) {
    v <- c(v, paste0("variant-position: chrom ", chrom, " off the written records"))
  }
  left <- tok("trinuc-context", 1L); ref <- tok("trinuc-context", 2L)
  altb <- tok("trinuc-context", 3L); right <- tok("trinuc-context", 4L)
  ctx <- sprintf("%s[%s>%s]%s", left, ref, altb, right)
  dna_len <- as.integer(ceiling(par$recs$size[1L] / 4L))
  bases1 <- tf_unpack(tail(g$rec_bytes[[1L]], dna_len), par$recs$size[1L])
  if (!identical(bases1[pos], ref)) v <- c(v, paste0("trinuc-context: ref off the bytes at ", pos))
  if (!identical(bases1[pos - 1L], left) || !identical(bases1[pos + 1L], right)) {
    v <- c(v, paste0("trinuc-context: flanks off the bytes at ", pos))
  }
  if (!(ctx %in% ev1("cat1@channels$labels"))) {
    v <- c(v, paste0("trinuc-context: ", ctx, " absent from the channel labels"))
  }
  n_checked <- n_checked + 3L
  for (k in c(1L, 2L)) {
    nm <- paste0("genome-pattern-chr", k)
    token <- tok(nm)
    bs <- tf_unpack(tail(g$rec_bytes[[k]],
                         as.integer(ceiling(par$recs$size[k] / 4L))), par$recs$size[k])
    head4 <- substr(paste0(bs, collapse = ""), 1L, 4L)
    mask <- if (k == 1L) par$nmask else integer(0)
    inm <- seq_along(bs) %in% mask
    out_idx <- which(!inm)
    a <- bs[1L]; b <- bs[2L]
    alt <- !identical(a, b) &&
      all(bs[out_idx] == c(b, a)[(out_idx %% 2L) + 1L]) &&
      (!length(mask) || all(bs[mask] == "T"))
    if (!identical(head4, token) || !alt) {
      v <- c(v, paste0(nm, ": prose says ", token, ", bytes re-derive ", head4))
    }
    n_checked <- n_checked + 1L
  }
  # the shared-writer claim: byte-identity against the test-suite helper
  if (is.na(sb$root) || !nzchar(sb$root)) sb$root <- .tf_root()
  helper <- file.path(sb$root, "tests", "testthat", "helper-tally.R")
  if (!file.exists(helper)) .tf_stop(paste0("test-suite helper writer unreachable: ", helper))
  he <- new.env(parent = baseenv())
  source(helper, local = he)
  hp <- tempfile("tour-face-helper-")
  he$.tally_write_2bit(hp)
  hb <- readBin(file(hp, "rb"), what = raw(), n = as.integer(file.size(hp)))
  if (!identical(hb, g$bytes)) {
    v <- c(v, "writer-identity: tour bytes off the shared helper writer")
  }
  n_checked <- n_checked + 1L
  # error-surface: the face must speak msuiter_error_* classes, live
  err <- sb$out[["errors"]]
  if (is.null(err)) .tf_stop("errors chunk produced no captured output")
  cls <- err[grepl("^condition class:", err)]
  if (length(cls) < 3L) v <- c(v, paste0("error-surface: only ", length(cls), " conditions surfaced"))
  if (any(grepl("no condition raised", err))) v <- c(v, "error-surface: a boundary stayed silent")
  if (!all(grepl("condition class: msuiter_error_", cls))) {
    v <- c(v, "error-surface: a condition speaks a foreign class")
  }
  n_checked <- n_checked + 1L
  list(violations = v, n_claims = nrow(claims), n_checked = n_checked)
}

# --- CLI main: the speaking face ---------------------------------------------------------------

# Runs unless the sourcing law face raised the shared marker.
if (!identical(Sys.getenv("MSUITER_TOOL_NO_MAIN", ""), "1")) {
  root <- .tf_root()
  page <- .tf_get("page")
  if (!nzchar(page)) page <- file.path(root, "vignettes", "tour.Rmd")
  suppressWarnings(library(msuiter))
  chunks <- tf_chunks(page)
  par <- tf_fixture_params(page, chunks)
  sb <- tf_sandbox(page, root)
  a <- tf_audit(page, sb, par)
  cat(paste0("TOUR-FACE CENSUS: page=", basename(page), " claims=", a$n_claims,
             " re-derived=", a$n_checked, " violations=", length(a$violations), "\n"))
  if (length(a$violations)) {
    for (x in a$violations) cat("VIOLATION: ", x, "\n", sep = "")
    quit(status = 1L)
  }
}
