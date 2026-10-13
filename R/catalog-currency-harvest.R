# catalog-currency-harvest.R: the updater leg helpers of the P5
# catalog-currency instrument (see R/catalog-currency.R for the mission
# header). Fetch-or-inject source handling, the exactly-one script-carrier
# extractor, the two document parsers and the byte-idempotent cache
# writers. Collated after catalog-currency-governance.R.
# ---------------------------------------------------------------------------
# Harvest: fetch (or inject) the official source documents and canonicalize
# their payload bytes. The parse is the ONLY place JSON is read; verification
# itself never needs it.
# ---------------------------------------------------------------------------

.ms_cc_require_json <- function(call = rlang::caller_call()) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    .ms_cc_abort(
      "the 'jsonlite' package is required to read the official release documents",
      i = "jsonlite is a Suggests dependency, used only when a source document is parsed",
      j = "install.packages(\"jsonlite\")",
      c = "install jsonlite, or consume a previously derived cache with ms_catalog_currency()",
      call = call
    )
  }
  asNamespace("jsonlite")
}

.ms_cc_json_parse <- function(text, what) {
  ns <- .ms_cc_require_json()
  out <- tryCatch(
    ns$fromJSON(text, simplifyVector = FALSE, simplifyDataFrame = FALSE,
                method = "fromString"),
    error = function(e) NULL
  )
  if (!is.list(out)) {
    .ms_cc_abort(
      sprintf("the %s document is not valid JSON", what),
      i = "the official page embeds the release/availability records as JSON script blocks",
      j = sprintf("first 40 bytes: %s", substr(text, 1L, 40L)),
      c = "re-run ms_catalog_currency_update() against the canonical page, or inject a fixed source"
    )
  }
  out
}

# Extract the verbatim JSON payload of <script id=".." ...> ... </script>.
# Exactly-one law: zero or several matching carriers are a hard stop, never
# a silent pick. R's gregexpr() with perl = TRUE returns whole-match STARTS
# as the values and their LENGTHS in the `match.length` attribute (it does
# NOT report capture-group offsets under perl), and encodes "no match" as a
# single -1 sentinel; we therefore key off starts>=1 && match.length>=0 and
# slice the payload ourselves (substring between the carrier's '>' and the
# next "</script>"). The payloads are JSON and never contain a nested
# "</script>", so the first closing tag terminates the block.
.ms_cc_extract_script <- function(html, script_id) {
  open_pat <- sprintf("<script[^>]*\\s+id=\"%s\"[^>]*>", script_id)
  starts <- gregexpr(open_pat, html, perl = TRUE)[[1L]]
  mlen <- attr(starts, "match.length")
  if (is.null(mlen)) {
    mlen <- integer(0)
  }
  valid <- which(!is.na(starts) & starts >= 1L &
                   seq_along(starts) <= length(mlen) &
                   !is.na(mlen[pmin(seq_along(starts), length(mlen))]) &
                   mlen[pmin(seq_along(starts), length(mlen))] >= 0L)
  n <- length(valid)
  if (n == 0L) {
    .ms_cc_abort(
      sprintf("the source document carries no <script id=\"%s\"> block", script_id),
      i = "the official downloads page embeds its release records in JSON script carriers",
      j = script_id,
      c = "inject a complete downloads-page capture via `source`, or omit `source` for the official-site fetch"
    )
  }
  if (n > 1L) {
    .ms_cc_abort(
      sprintf("the source document carries %d <script id=\"%s\"> blocks; exactly one is required",
              n, script_id),
      i = "ambiguous governance carriers fail closed -- never first-wins",
      j = script_id,
      c = "supply a clean single-carrier capture via `source`"
    )
  }
  open_end <- starts[valid[1L]] + mlen[valid[1L]] - 1L
  rest <- substring(html, open_end + 1L)
  # regexpr() returns an ATOMIC integer vector whose match.length lives in an
  # attribute -- index with [1] (NOT [[1]], which would strip the attribute).
  close_pos <- regexpr(.MS_CC_SCRIPT_CLOSE, rest, fixed = TRUE)
  close_len <- attr(close_pos, "match.length")
  if (!length(close_pos) || is.na(close_pos[1L]) || close_pos[1L] < 1L ||
      is.null(close_len) || length(close_len) < 1L ||
      is.na(close_len[1L]) || close_len[1L] < 0L) {
    .ms_cc_abort(
      sprintf("the <script id=\"%s\"> block is not terminated by a closing tag", script_id),
      i = "the canonical carrier must close before the next block",
      j = script_id,
      c = "inject a complete downloads-page capture via `source`"
    )
  }
  substring(rest, 1L, close_pos[1L] - 1L)
}

.ms_cc_download_page <- function(url) {
  dest <- file.path(tempdir(), paste0("p5cc-page-", sample.int(1e6, 1L), ".html"))
  ok <- tryCatch({
    download.file(url, dest, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok || !file.exists(dest) || file.info(dest)$size <= 0L) {
    unlink(dest)
    .ms_cc_abort(
      "the official COSMIC downloads page could not be fetched",
      i = "the default fetch talks to the canonical page over https once per invocation",
      j = url,
      c = "check connectivity, or work offline: ms_catalog_currency_update(source = <path>, offline = TRUE)"
    )
  }
  on.exit(unlink(dest))
  raw <- readBin(dest, "raw", min(file.info(dest)$size, .MS_CC_MAX_SOURCE_BYTES))
  if (file.info(dest)$size > .MS_CC_MAX_SOURCE_BYTES) {
    .ms_cc_abort(
      "the fetched downloads page is unreasonably large",
      i = sprintf("pages above %d bytes are refused as a guard", as.integer(.MS_CC_MAX_SOURCE_BYTES)),
      j = url,
      c = "verify the endpoint before re-running"
    )
  }
  rawToChar(raw)
}

# Reads a bounded file as raw bytes -> UTF-8 character (byte-faithful).
.ms_cc_read_text <- function(path, what) {
  size <- file.info(path)$size
  if (is.na(size) || size > .MS_CC_MAX_SOURCE_BYTES) {
    .ms_cc_abort(
      sprintf("%s is missing or unreasonably large", what),
      i = sprintf("source documents are capped at %d bytes", as.integer(.MS_CC_MAX_SOURCE_BYTES)),
      j = path,
      c = "re-run ms_catalog_currency_update() against a faithful capture"
    )
  }
  rawToChar(readBin(path, "raw", size))
}

# Returns list(ref_text, avail_text, origin). Byte contract: the returned
# texts are the canonical payloads themselves -- the verbatim JSON as the
# official carrier holds it.
.ms_cc_harvest <- function(source, page_url, offline) {
  if (is.null(source)) {
    if (offline) {
      .ms_cc_abort(
        "offline mode cannot perform the default official-site fetch",
        i = "with `offline = TRUE` no network leg is attempted by construction",
        j = "source = NULL",
        c = "inject a captured source with `source` (a page file or a split document directory), or allow the fetch with offline = FALSE"
      )
    }
    html <- .ms_cc_download_page(page_url)
    list(
      ref_text = .ms_cc_extract_script(html, .MS_CC_DOC_SCRIPT_ID[["reference_data"]]),
      avail_text = .ms_cc_extract_script(html, .MS_CC_DOC_SCRIPT_ID[["availability_data"]]),
      origin = list(mode = "network", location = page_url)
    )
  } else if (dir.exists(source)) {
    # file.path() pastes through the first (unnamed) argument, so the key
    # names must be re-attached to index `need` by document key below.
    need <- setNames(file.path(source, unname(.MS_CC_DOC_FILE[.MS_CC_DOC_KEYS])),
                     .MS_CC_DOC_KEYS)
    missing <- need[!file.exists(need)]
    if (length(missing)) {
      .ms_cc_abort(
        sprintf("the split-directory source is missing '%s'",
                paste(basename(missing), collapse = "', '")),
        i = "the split form carries one canonical JSON payload file per governed document",
        j = source,
        c = sprintf("provide %s and %s in the directory",
                    .MS_CC_DOC_FILE[["reference_data"]],
                    .MS_CC_DOC_FILE[["availability_data"]])
      )
    }
    list(
      ref_text = .ms_cc_read_text(need[["reference_data"]], "the injected reference document"),
      avail_text = .ms_cc_read_text(need[["availability_data"]], "the injected availability document"),
      origin = list(mode = "source-dir", location = source)
    )
  } else {
    html <- .ms_cc_read_text(source, "the injected source document")
    list(
      ref_text = .ms_cc_extract_script(html, .MS_CC_DOC_SCRIPT_ID[["reference_data"]]),
      avail_text = .ms_cc_extract_script(html, .MS_CC_DOC_SCRIPT_ID[["availability_data"]]),
      origin = list(mode = "source-file", location = source)
    )
  }
}

.ms_cc_parse_reference <- function(text) {
  doc <- .ms_cc_json_parse(text, "reference (release list)")
  rel <- doc[["releases"]][["human_cancer"]]
  if (!is.list(rel) || !length(rel)) {
    .ms_cc_abort(
      "the reference document names no human_cancer releases",
      i = "the releases.releases.human_cancer block is the currency spine",
      j = "(empty or absent)",
      c = "re-run against the canonical page or a faithful capture"
    )
  }
  versions <- vapply(rel, function(r) {
    v <- unlist(r[["version"]])
    if (!is.character(v) || length(v) != 1L || !nzchar(v)) {
      .ms_cc_abort(
        "a release entry in the reference document carries no version label",
        i = "every human_cancer release must be addressable by label",
        j = msuiter_quote_trunc(names(r)),
        c = "re-run against a faithful capture of the official page"
      )
    }
    .ms_cc_check_version(v, "a release label")
    v
  }, character(1L))
  list(releases = unname(versions))
}

# From the availability document: the class/build/profile_count shape of one
# release. Shape facts only -- the document's own numbers are profile COUNTS
# (structure), and no per-signature values exist in it or are read.
.ms_cc_parse_availability <- function(text, structure_release) {
  doc <- .ms_cc_json_parse(text, "availability (structural)")
  hc <- doc[["human_cancer"]][[structure_release]]
  if (!is.list(hc) || !length(hc)) {
    .ms_cc_abort(
      sprintf("the availability document carries no structure for release '%s'", structure_release),
      i = "the availability document must describe the release being certified",
      j = structure_release,
      c = "re-run against a faithful capture of the official page"
    )
  }
  structure <- list()
  for (cl in names(hc)) {
    cell <- list()
    for (bd in names(hc[[cl]])) {
      n <- unlist(hc[[cl]][[bd]][["profile_count"]])
      if (!is.numeric(n) && !is.character(n)) {
        n <- NA_real_
      }
      n <- suppressWarnings(as.numeric(n))
      if (length(n) != 1L || is.na(n) || n < 0 || n > 1e5) {
        .ms_cc_abort(
          sprintf("the availability document carries a malformed profile_count for '%s/%s'", cl, bd),
          i = "profile counts are the structural cells the official release publishes",
          j = sprintf("received: %s", msuiter_quote_trunc(n)),
          c = "re-run against a faithful capture of the official page"
        )
      }
      cell[[bd]] <- as.integer(n)
    }
    structure[[cl]] <- cell
  }
  .ms_cc_validate_structure(structure, "harvested structure")
  structure
}

# ---------------------------------------------------------------------------
# Cache plumbing (GITIGNORED derivation dir, like bench/g0/cache/).
# ---------------------------------------------------------------------------

.ms_cc_default_cache_dir <- function() {
  opt <- getOption("msuiter.catalog_currency.cache_dir", default = NULL)
  if (is.character(opt) && length(opt) == 1L && nzchar(opt)) {
    return(opt)
  }
  env <- Sys.getenv("MSUITER_CATALOG_CURRENCY_CACHE_DIR")
  if (nzchar(env)) {
    return(env)
  }
  tools::R_user_cache_dir("msuiter", "catalog-currency", expand = TRUE, ragged = FALSE)
}

.ms_cc_write_verbatim <- function(path, text) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(text), con)
  path
}

.ms_cc_record_path <- function(cache) file.path(cache, .MS_CC_RECORD_FILE)
.ms_cc_candidate_path <- function(cache) file.path(cache, .MS_CC_CANDIDATE_FILE)
.ms_cc_doc_path <- function(cache, key)
  file.path(cache, .MS_CC_SOURCES_DIR, .MS_CC_DOC_FILE[[key]])

# The cache record: what was harvested, canonically, from where. Derived
# facts only (no timestamps, no randomness) so re-derivation is
# byte-idempotent.
.ms_cc_build_record <- function(origin, doc_states, releases, latest, structure_release,
                                structure, page_url) {
  documents <- list()
  for (k in .MS_CC_DOC_KEYS) {
    documents[[k]] <- list(
      url = page_url,
      script_id = .MS_CC_DOC_SCRIPT_ID[[k]],
      file = file.path(.MS_CC_SOURCES_DIR, .MS_CC_DOC_FILE[[k]]),
      sha256 = .ms_cc_sha256_text(doc_states[[k]]$text),
      bytes = as.integer(length(charToRaw(doc_states[[k]]$text)))
    )
  }
  list(
    schema_version = .MS_CC_SCHEMA,
    kind = .MS_CC_RECORD_KIND,
    generator = paste0("msuiter-", as.character(utils::packageVersion("msuiter"))),
    origin = origin,
    documents = documents,
    releases = releases,
    latest_release = latest,
    structure_release = structure_release,
    structure = structure
  )
}
