# test-catalog-currency.R: the P5 catalog-currency instrument (parity plan
# docs/research/09 section 5, phase P5; refdb governance pattern of
# data-raw/build_refdb.R + R/refdb.R).
#
# Contract under test:
#   * ms_catalog_registry()  -- the committed provenance sidecar digest
#     registry: schema gate (fail-closed), structural whitelist, D3-safe
#     numeric bounds, agreement with the live refdb governance manifest;
#   * ms_catalog_currency_update() -- the updater: injected-source mode
#     (page file or split dir), canonical byte extraction into the
#     GITIGNORED cache, SHA-256 digests, byte-idempotent re-derivation;
#   * ms_catalog_currency() -- the verifier: cache-vs-record integrity
#     (corrupt/missing), cache-vs-registry drift, pinned-vs-latest version
#     resolution (current/behind/ahead), refdb cross-check (inconsistent);
#   * boundary argument validation for every user-facing argument
#     (msuiter_error_catalog_currency + full i/j/c bullets).
#
# D3 law: every source document here is synthetic (9.x / 3.x synthetic
# bands, trivial 1/2/3 profile counts); no COSMIC numeric content enters
# any fixture, cache copy or expectation. The whole file is OFFLINE: the
# network leg lives in the instrument's own default path and is exercised
# only by the live-site check below, which is explicitly environment-gated.

# -- shared local probe: catalog-currency errors carry the house bullets ----
.cc_expect_cc_error <- function(expr, regexp = NULL, info = NULL) {
  err <- tryCatch(
    {
      expr
      NULL
    },
    msuiter_error_catalog_currency = function(e) e,
    error = function(e) e
  )
  if (is.null(err)) {
    stop("expected an msuiter_error_catalog_currency condition ",
         if (!is.null(info)) paste0("(", info, ")") else "", call. = FALSE)
  }
  expect_s3_class(err, "condition")
  if (!inherits(err, "msuiter_error_catalog_currency")) {
    stop("wrong error class: ", paste(class(err), collapse = "/"),
         if (!is.null(info)) paste0(" (", info, ")") else "", call. = FALSE)
  }
  if (!is.null(regexp)) {
    expect_match(conditionMessage(err), regexp)
  }
  parts <- err$msuiter_error
  expect_true(is.list(parts) && all(c("i", "j", "c") %in% names(parts)))
  for (nm in c("i", "j", "c")) {
    expect_true(is.character(parts[[nm]]) && length(parts[[nm]]) == 1L && nzchar(parts[[nm]]),
                info = paste0("bullet '", nm, "' must be a non-empty string"))
  }
  invisible(err)
}

# Walk every numeric leaf of the registry: D3-safe by construction, the
# registry may only ever hold small structural ints (counts/sizes), never
# vectors of numeric content.
.cc_numeric_leaves <- function(x, acc = list()) {
  if (is.numeric(x)) {
    acc[[length(acc) + 1L]] <- x
  } else if (is.list(x)) {
    for (e in x) acc <- .cc_numeric_leaves(e, acc)
  }
  acc
}

# ===========================================================================
# A. The committed registry: schema gate + structural contract
# ===========================================================================

test_that("ms_catalog_registry loads the committed sidecar with the schema gate on", {
  reg <- ms_catalog_registry()
  expect_true(is.list(reg))
  expect_identical(reg$schema_version, "1")
  expect_identical(reg$kind, "catalog-currency-registry")
  expect_identical(reg$package, "msuiter")
  expect_identical(reg$pinned_release, "3.6")
  # Mirror provenance (labels + commit hex only -- no content).
  expect_match(reg$mirror$repo, "^SigProfilerSuite/SigProfilerAssignment$")
  expect_match(reg$mirror$commit, "^[0-9a-f]{40,64}$")
  expect_identical(reg$mirror$license, "BSD-2-Clause")
  # refdb cross-reference pointers.
  expect_match(reg$refdb$version, "^v[0-9.]+$")
  expect_true(is.character(reg$refdb$governed_files) &&
                length(reg$refdb$governed_files) >= 1L)
  # Official leg: documented canonical URLs and measured document digests.
  expect_match(reg$official$page_url, "^https://cancer\\.sanger\\.ac\\.uk/")
  expect_match(reg$official$site_root, "^https://cancer\\.sanger\\.ac\\.uk/?$")
  expect_setequal(names(reg$official$documents), c("reference_data", "availability_data"))
  for (d in reg$official$documents) {
    expect_match(d$sha256, "^[0-9a-f]{64}$")
    expect_true(d$script_id %in% c("reference-data", "availability-data"))
    expect_true(d$bytes > 0L && d$bytes < 1e6)
  }
  expect_true("3.6" %in% reg$official$releases)
  expect_identical(reg$official$latest_release, "3.6")
  # The matrix-bytes leg: login-gated upstream, MUST stay UNMEASURED and
  # must never smuggle digests or numbers (anti-fabrication law).
  expect_identical(reg$matrix_bytes$status, "UNMEASURED")
  expect_null(reg$matrix_bytes$sha256)
  expect_true(is.character(reg$matrix_bytes$policy) && nzchar(reg$matrix_bytes$policy))
})

test_that("the registry passes the D3 numeric-bounds walk", {
  reg <- ms_catalog_registry()
  leaves <- .cc_numeric_leaves(reg)
  expect_true(length(leaves) >= 1L) # at least the per-document byte sizes
  for (lv in leaves) {
    expect_true(length(lv) == 1L, info = "registry numeric vectors must be scalars")
    expect_true(isTRUE(all(lv >= 0 & lv <= 1e5)),
                info = "registry numerics are bounded structural counts only")
  }
})

test_that("ms_catalog_registry refuses a forward schema (fail-closed)", {
  reg <- ms_catalog_registry()
  reg$schema_version <- "2"
  path <- file.path(tempdir(), paste0("reg-fwd-", sample.int(1e6, 1L), ".rds"))
  saveRDS(reg, path, version = 2L)
  .cc_expect_cc_error(
    ms_catalog_registry(path = path),
    regexp = "schema_version"
  )
})

test_that("ms_catalog_registry fails structured on missing or unreadable sidecars", {
  missing <- file.path(tempdir(), paste0("nope-", sample.int(1e6, 1L), ".rds"))
  .cc_expect_cc_error(ms_catalog_registry(path = missing), regexp = "registry")
  junk <- file.path(tempdir(), paste0("junk-", sample.int(1e6, 1L), ".rds"))
  .cc_write_bytes(junk, "this is not an rds file")
  .cc_expect_cc_error(ms_catalog_registry(path = junk), regexp = "registry")
})

test_that("the registry agrees with the live refdb governance manifest", {
  reg <- ms_catalog_registry()
  man <- ms_refdb_manifest() # itself fail-closed over the shipped bytes
  expect_identical(reg$refdb$version, man$version) # "v3.6"
  expect_identical(
    sort(reg$refdb$governed_files),
    sort(names(man$files))
  )
  expect_identical(reg$mirror$commit, man$upstream$commit)
  expect_identical(reg$mirror$repo, man$upstream$repo)
})

test_that("ms_catalog_registry validates its own boundary arguments", {
  .cc_expect_cc_error(ms_catalog_registry(path = 42), regexp = "path")
  .cc_expect_cc_error(ms_catalog_registry(path = NA_character_), regexp = "path")
  .cc_expect_cc_error(ms_catalog_registry(path = c("a", "b")), regexp = "path")
})

# ===========================================================================
# B. The updater: injected-source mode (offline by construction)
# ===========================================================================

test_that("update from an injected source page lays the canonical cache", {
  skip_if_not_installed("jsonlite") # harvest parses the official JSON shape
  cache <- .cc_tmp_cache("fresh-page")
  src <- .cc_source_page()
  rep <- ms_catalog_currency_update(source = src, cache = cache, offline = TRUE)
  expect_s3_class(rep, "ms_catalog_currency_report")
  expect_true(rep$cache$present)
  ref_f <- file.path(cache, .CC_SOURCES_DIR, .CC_REF_FILE)
  ava_f <- file.path(cache, .CC_SOURCES_DIR, .CC_AVAIL_FILE)
  rec_f <- file.path(cache, .CC_RECORD_FILE)
  cand_f <- file.path(cache, .CC_CANDIDATE_FILE)
  expect_true(all(file.exists(c(ref_f, ava_f, rec_f, cand_f))))
  # Extracted payloads are the verbatim embedded JSON (byte contract).
  expect_identical(.cc_read_bytes(ref_f), .cc_reference_payload(.CC_FIXTURE_RELEASES))
  expect_identical(.cc_read_bytes(ava_f), .cc_availability_payload(.CC_FIXTURE_AVAIL))
  rec <- readRDS(rec_f)
  expect_identical(rec$kind, "catalog-currency-record")
  expect_identical(rec$schema_version, "1")
  expect_identical(rec$origin$mode, "source-file")
  expect_identical(rec$origin$location, normalizePath(src, mustWork = FALSE))
  expect_identical(rec$releases, .CC_FIXTURE_RELEASES)
  expect_identical(rec$latest_release, "9.9")
  expect_identical(rec$structure_release, "9.9")
  expect_named(rec$documents)
  expect_false(any(duplicated(names(rec$documents))))
  expect_setequal(names(rec$documents), c("reference_data", "availability_data"))
  for (d in rec$documents) {
    expect_match(d$sha256, "^[0-9a-f]{64}$")
    expect_true(d$bytes > 0L)
  }
})

test_that("document digests match an independent SHA-256 tool over the cache bytes", {
  skip_if_not_installed("jsonlite")
  cache <- .cc_tmp_cache("sha-xcheck")
  ms_catalog_currency_update(source = .cc_source_page(tag = "sha-src"),
                             cache = cache, offline = TRUE)
  for (f in c(.CC_REF_FILE, .CC_AVAIL_FILE)) {
    path <- file.path(cache, .CC_SOURCES_DIR, f)
    sys <- .cc_system_sha256(path)
    if (is.null(sys)) skip("no system SHA-256 tool available: the platform shasum/sha256sum is not installed")
    rec <- readRDS(file.path(cache, .CC_RECORD_FILE))
    # file name -> document key (reference_data.json -> reference_data)
    key <- sub("\\.json$", "", f)
    expect_identical(rec$documents[[key]]$sha256, sys)
  }
})

test_that("the split-directory source form is byte-equivalent to the page form", {
  skip_if_not_installed("jsonlite")
  cache_p <- .cc_tmp_cache("form-page")
  cache_d <- .cc_tmp_cache("form-dir")
  ms_catalog_currency_update(source = .cc_source_page(tag = "cmp-page"),
                             cache = cache_p, offline = TRUE)
  ms_catalog_currency_update(source = .cc_source_dir(tag = "cmp-dir"),
                             cache = cache_d, offline = TRUE)
  rp <- readRDS(file.path(cache_p, .CC_RECORD_FILE))
  rd <- readRDS(file.path(cache_d, .CC_RECORD_FILE))
  expect_identical(rp$documents$reference_data$sha256,
                   rd$documents$reference_data$sha256)
  expect_identical(rp$documents$availability_data$sha256,
                   rd$documents$availability_data$sha256)
  expect_identical(rp$releases, rd$releases)
  expect_identical(rd$origin$mode, "source-dir")
})

test_that("re-deriving from the same source is byte-idempotent", {
  skip_if_not_installed("jsonlite")
  src <- .cc_source_page(tag = "idem")
  cache <- .cc_tmp_cache("idem")
  ms_catalog_currency_update(source = src, cache = cache, offline = TRUE)
  first <- lapply(c(file.path(cache, .CC_SOURCES_DIR, c(.CC_REF_FILE, .CC_AVAIL_FILE)),
                    file.path(cache, c(.CC_RECORD_FILE, .CC_CANDIDATE_FILE))),
                  .cc_read_raw)
  ms_catalog_currency_update(source = src, cache = cache, offline = TRUE)
  second <- lapply(c(file.path(cache, .CC_SOURCES_DIR, c(.CC_REF_FILE, .CC_AVAIL_FILE)),
                     file.path(cache, c(.CC_RECORD_FILE, .CC_CANDIDATE_FILE))),
                   .cc_read_raw)
  expect_identical(first, second)
})

test_that("update keeps the offline law: source NULL + offline refuses with a fix", {
  skip_if_not_installed("jsonlite")
  cache <- .cc_tmp_cache("offline-refuse")
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = NULL, cache = cache, offline = TRUE),
    regexp = "offline"
  )
})

test_that("update validates its boundary arguments", {
  skip_if_not_installed("jsonlite")
  cache <- .cc_tmp_cache("argupd")
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = 42, cache = cache), regexp = "source"
  )
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = "no/such/page.html", cache = cache, offline = TRUE),
    regexp = "source"
  )
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = .cc_source_page(tag = "argupd2"), cache = 7),
    regexp = "cache"
  )
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = .cc_source_page(tag = "argupd3"),
                               cache = cache, offline = "yes"),
    regexp = "offline"
  )
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = .cc_source_page(tag = "argupd4"),
                               cache = cache, offline = NA),
    regexp = "offline"
  )
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = .cc_source_page(tag = "argupd5"),
                               cache = cache, registry = 1:2),
    regexp = "registry"
  )
})

test_that("update rejects malformed source documents with structured errors", {
  skip_if_not_installed("jsonlite")
  cache <- .cc_tmp_cache("badsrc")
  # Page without the required script blocks.
  bare <- .cc_tmp_cache("badsrc-page")
  p <- file.path(bare, "bare.html")
  .cc_write_bytes(p, "<html><body>nothing to extract</body></html>\n")
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = p, cache = cache, offline = TRUE),
    regexp = "reference-data|script"
  )
  # Page with a duplicated block is ambiguous -> refuse, never first-wins.
  dup <- .cc_tmp_cache("badsrc-dup")
  p2 <- file.path(dup, "dup.html")
  one <- .cc_reference_payload(.CC_FIXTURE_RELEASES)
  .cc_write_bytes(p2, paste0("<html><body>",
                             '<script id="reference-data" type="application/json">', one, '</script>',
                             '<script id="reference-data" type="application/json">', one, '</script>',
                             "</body></html>\n"))
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = p2, cache = cache, offline = TRUE),
    regexp = "exactly one|reference-data"
  )
  # Split dir missing one of the two canonical files.
  half <- .cc_tmp_cache("badsrc-half")
  .cc_write_bytes(file.path(half, .CC_REF_FILE), .cc_reference_payload(.CC_FIXTURE_RELEASES))
  .cc_expect_cc_error(
    ms_catalog_currency_update(source = half, cache = cache, offline = TRUE),
    regexp = "availability_data"
  )
})

# ===========================================================================
# C. The verifier: integrity, drift, version resolution, refdb cross-check
# ===========================================================================

.cc_update_ok <- function(cache, src) {
  skip_if_not_installed("jsonlite")
  ms_catalog_currency_update(source = src, cache = cache, offline = TRUE)
}

# A registry copy whose official leg agrees with the given cache's record.
.cc_registry_matching <- function(cache) {
  rec <- readRDS(file.path(cache, .CC_RECORD_FILE))
  .cc_registry_copy(official_from_record = rec)
}

test_that("verify on a clean matching cache+registry is ok/current", {
  cache <- .cc_tmp_cache("ok")
  # latest == pinned scenario: synthetic page in the 3.x band at 3.6.
  src <- .cc_source_page(tag = "ok",
                         releases = c("3.6", "3.5", "3.4"),
                         avail = list("3.6" = list("SBS-96" = c(GRCh37 = 3L, GRCh38 = 3L),
                                                  "DBS-78" = c(GRCh37 = 2L))))
  .cc_update_ok(cache, src)
  rep <- ms_catalog_currency(cache = cache, registry = .cc_registry_matching(cache))
  expect_s3_class(rep, "ms_catalog_currency_report")
  expect_identical(rep$verdict, "ok")
  expect_identical(rep$version_state, "current")
  expect_identical(rep$latest$status, "measured")
  expect_identical(rep$latest$release, "3.6")
  expect_identical(rep$available$status, "measured")
  expect_identical(rep$available$releases, c("3.6", "3.5", "3.4"))
  for (d in rep$cache$docs) expect_identical(d$state, "ok")
})

test_that("verify reports no-cache with an actionable fix, not an error", {
  cache <- file.path(tempdir(), paste0("p5cc-absent-", sample.int(1e6, 1L)))
  rep <- ms_catalog_currency(cache = cache)
  expect_identical(rep$verdict, "no-cache")
  expect_false(rep$cache$present)
  expect_identical(rep$version_state, "unknown")
  expect_identical(rep$latest$status, "unmeasured")
  expect_true(any(grepl("update", rep$hints, ignore.case = TRUE)))
})

test_that("a missing cached document file is reported as missing", {
  cache <- .cc_tmp_cache("miss")
  .cc_update_ok(cache, .cc_source_page(tag = "miss-src"))
  unlink(file.path(cache, .CC_SOURCES_DIR, .CC_AVAIL_FILE))
  rep <- ms_catalog_currency(cache = cache, registry = .cc_registry_matching(cache))
  expect_identical(rep$verdict, "corrupt") # integrity violation overall
  expect_identical(rep$cache$docs$availability_data$state, "missing")
  expect_identical(rep$cache$docs$reference_data$state, "ok")
  expect_identical(rep$version_state, "unknown")
})

test_that("one corrupted byte in a cached document is caught as corrupt", {
  cache <- .cc_tmp_cache("corrupt")
  .cc_update_ok(cache, .cc_source_page(tag = "corrupt-src"))
  ref_f <- file.path(cache, .CC_SOURCES_DIR, .CC_REF_FILE)
  flipped <- sub("9\\.9", "9.8", .cc_read_bytes(ref_f), fixed = FALSE)
  .cc_write_bytes(ref_f, flipped)
  rep <- ms_catalog_currency(cache = cache, registry = .cc_registry_matching(cache))
  expect_identical(rep$verdict, "corrupt")
  expect_identical(rep$cache$docs$reference_data$state, "corrupt")
  expect_match(rep$cache$docs$reference_data$record_sha, "^[0-9a-f]{64}$")
  expect_match(rep$cache$docs$reference_data$cached, "^[0-9a-f]{64}$")
  expect_false(rep$cache$docs$reference_data$record_sha ==
               rep$cache$docs$reference_data$cached)
  expect_identical(rep$version_state, "unknown") # untrusted record
})

test_that("an unreadable cache record fails structured (fail-closed)", {
  cache <- .cc_tmp_cache("badrec")
  .cc_update_ok(cache, .cc_source_page(tag = "badrec-src"))
  .cc_write_bytes(file.path(cache, .CC_RECORD_FILE), "junk-bytes")
  .cc_expect_cc_error(ms_catalog_currency(cache = cache), regexp = "record")
})

test_that("cache-vs-registry drift is reported per document with both digests", {
  cache <- .cc_tmp_cache("drift")
  .cc_update_ok(cache, .cc_source_page(tag = "drift-src"))
  reg <- ms_catalog_registry()
  reg$official$documents$reference_data$sha256 <- strrep("0", 64L)
  path <- file.path(tempdir(), paste0("reg-drift-", sample.int(1e6, 1L), ".rds"))
  saveRDS(reg, path, version = 2L)
  rep <- ms_catalog_currency(cache = cache, registry = path)
  expect_identical(rep$verdict, "drift")
  d <- rep$cache$docs$reference_data
  expect_identical(d$state, "drift")
  expect_identical(d$expected, strrep("0", 64L))
  rec <- readRDS(file.path(cache, .CC_RECORD_FILE))
  expect_identical(d$cached, rec$documents$reference_data$sha256)
  # integrity holds, so the version legs still speak (upstream moved).
  expect_identical(rep$version_state, "behind") # 9.9 > pinned 3.6
})

test_that("pinned-vs-latest resolution covers behind and ahead", {
  # behind: synthetic latest 3.7 above the pinned 3.6.
  cache_b <- .cc_tmp_cache("behind")
  .cc_update_ok(cache_b, .cc_source_page(tag = "behind-src",
                                         releases = c("3.7", "3.6"),
                                         avail = list("3.7" = list("SBS-96" = c(GRCh37 = 3L)),
                                                    "3.6" = list("SBS-96" = c(GRCh37 = 2L)))))
  rep_b <- ms_catalog_currency(cache = cache_b, registry = .cc_registry_matching(cache_b))
  expect_identical(rep_b$verdict, "behind")
  expect_identical(rep_b$version_state, "behind")
  expect_identical(rep_b$latest$release, "3.7")
  expect_true(any(grepl("3.7", rep_b$messages)))

  # ahead: synthetic latest 3.5 under the pinned 3.6 (registry moved first).
  cache_a <- .cc_tmp_cache("ahead")
  .cc_update_ok(cache_a, .cc_source_page(tag = "ahead-src",
                                         releases = c("3.5", "3.4"),
                                         avail = list("3.5" = list("SBS-96" = c(GRCh37 = 1L)),
                                                    "3.4" = list("SBS-96" = c(GRCh37 = 1L)))))
  rep_a <- ms_catalog_currency(cache = cache_a, registry = .cc_registry_matching(cache_a))
  expect_identical(rep_a$verdict, "ok") # integrity fine; the state speaks
  expect_identical(rep_a$version_state, "ahead")
})

test_that("verdict precedence: corrupt outranks drift, inconsistent outranks all", {
  cache <- .cc_tmp_cache("prec")
  .cc_update_ok(cache, .cc_source_page(tag = "prec-src"))
  # Corrupt one file AND drift the registry: corrupt must win.
  ref_f <- file.path(cache, .CC_SOURCES_DIR, .CC_REF_FILE)
  .cc_write_bytes(ref_f, "x")
  reg <- ms_catalog_registry()
  reg$official$documents$availability_data$sha256 <- strrep("f", 64L)
  reg_path <- file.path(tempdir(), paste0("reg-prec-", sample.int(1e6, 1L), ".rds"))
  saveRDS(reg, reg_path, version = 2L)
  rep <- ms_catalog_currency(cache = cache, registry = reg_path)
  expect_identical(rep$verdict, "corrupt")
  # A refdb disagreement outranks the corrupt state.
  bad_man <- list(version = "v9.9", files = list(x = list()),
                  upstream = list(repo = ms_refdb_manifest()$upstream$repo,
                                 commit = ms_refdb_manifest()$upstream$commit))
  rep2 <- ms_catalog_currency(cache = cache, registry = reg_path,
                              refdb_manifest = bad_man)
  expect_identical(rep2$verdict, "inconsistent")
  expect_true(any(grepl("v9.9", rep2$pinned$refdb_findings)))
})

test_that("refdb cross-check flags mirror or version disagreement", {
  rep <- ms_catalog_currency(cache = .cc_tmp_cache("refdb-clean"), # no-cache verdict
                              refdb_manifest = NULL)
  expect_identical(rep$verdict, "no-cache")
  bad <- ms_refdb_manifest()
  bad$version <- "v7.7"
  rep2 <- ms_catalog_currency(cache = .cc_tmp_cache("refdb-bad"), refdb_manifest = bad)
  expect_identical(rep2$verdict, "inconsistent")
  expect_true(any(grepl("v7.7", rep2$pinned$refdb_findings)))
  # A malformed injected manifest is refused, not trusted.
  .cc_expect_cc_error(
    ms_catalog_currency(cache = .cc_tmp_cache("refdb-malformed"),
                        refdb_manifest = list(version = 1:3)),
    regexp = "refdb_manifest"
  )
})

test_that("verify validates its boundary arguments", {
  .cc_expect_cc_error(ms_catalog_currency(cache = 42), regexp = "cache")
  .cc_expect_cc_error(ms_catalog_currency(cache = ""), regexp = "cache")
  .cc_expect_cc_error(ms_catalog_currency(cache = c("a", "b")), regexp = "cache")
  .cc_expect_cc_error(
    ms_catalog_currency(cache = .cc_tmp_cache("argver"), registry = NA),
    regexp = "registry"
  )
  .cc_expect_cc_error(
    ms_catalog_currency(cache = .cc_tmp_cache("argver2"), refdb_manifest = "list-please"),
    regexp = "refdb_manifest"
  )
})

# ===========================================================================
# D. Hygiene: synthetic sentinel, golden fixture, print surface
# ===========================================================================

test_that("the committed fixture is self-evidently synthetic (D3 sentinel)", {
  txt <- .cc_read_bytes(.cc_fixture_path())
  expect_match(txt, "SYNTHETIC FIXTURE")
  expect_match(txt, "not COSMIC data|NO COSMIC numeric content")
  # trivial synthetic values only: the profile_count universe is {1,2,3}
  # (gregexpr reports whole-match offsets only -- slice the whole match and
  # strip the key prefix, the documented house idiom).
  hits <- gregexpr('"profile_count":[0-9]+', txt, perl = TRUE)[[1L]]
  hlen <- attr(hits, "match.length")
  valid <- which(!is.na(hits) & hits >= 1L & !is.na(hlen) & hlen >= 0L)
  toks <- substring(txt, hits[valid], hits[valid] + hlen[valid] - 1L)
  counts <- as.integer(sub('^"profile_count":', '', toks))
  counts <- counts[!is.na(counts)]
  expect_true(length(counts) >= 1L)
  expect_true(all(counts <= 3L))
})

test_that("the golden fixture equals the helper-generated page byte for byte", {
  expect_identical(.cc_read_bytes(.cc_fixture_path()), .cc_fixture_page())
})

test_that("the report prints a compact drift summary and returns itself", {
  cache <- .cc_tmp_cache("print")
  .cc_update_ok(cache, .cc_source_page(tag = "print-src"))
  rep <- ms_catalog_currency(cache = cache, registry = .cc_registry_matching(cache))
  out <- capture.output(res <- print(rep))
  expect_identical(res, rep)
  expect_true(any(grepl("verdict", out, ignore.case = TRUE)))
  expect_true(any(grepl("pinned", out, ignore.case = TRUE)))
  expect_true(any(grepl("latest", out, ignore.case = TRUE)))
})

# ===========================================================================
# E. The live official-site leg -- environment-gated, never a silent skip
# ===========================================================================

test_that("the documented official endpoint is the documented official endpoint", {
  reg <- ms_catalog_registry()
  # Structural law only (no network here): the registry must speak the
  # canonical Sanger host and the downloads page path.
  expect_match(reg$official$page_url,
               "^https://cancer\\.sanger\\.ac\\.uk/signatures/downloads/$")
  expect_identical(reg$official$documents$reference_data$url, reg$official$page_url)
  expect_identical(reg$official$documents$availability_data$url, reg$official$page_url)
})

# ===========================================================================
# F. digest-gate and cache-dir resolution (CI warning-zero, 2026-10-23)
# ===========================================================================
# The check scan of push-run 39864490318 printed
#   'loadNamespace' or 'requireNamespace' call not declared from: 'digest'
#   Missing or unexported object: 'tools::R_user_cache_dir'
# The remedy was declaration (Suggests: digest, R6) and the exported
# tools::R_user_dir(which = "cache") route. These units pin what the scan
# cannot: that both gate paths compute the SAME bytes and that the cache-dir
# precedence actually resolves -- a declaration-only fix without functional
# proof would leave the optional-accelerator family untested.

test_that("the digest accelerator gate is byte-identical to the pure-R kernel (F1)", {
  payloads <- list(ascii = charToRaw("catalog-currency"),
                   empty = charToRaw(""),
                   span  = as.raw(0L:255L))
  pure  <- sapply(payloads, function(p) msuiter:::.ms_fit_sha256(p))
  gated <- sapply(payloads, function(p) msuiter:::.ms_cc_sha256_raw(p))
  expect_identical(pure, gated)
  if (requireNamespace("digest", quietly = TRUE)) {
    direct <- sapply(payloads, function(p) {
      asNamespace("digest")$digest(p, algo = "sha256", serialize = FALSE)
    })
    expect_identical(direct, gated)
  }
})

test_that("with digest unloadable the gate falls back byte-identically (F2)", {
  # The gate's absent leg MEASURED, not simulated: a fresh Rscript process
  # runs with R_LIBS_USER pointed at a directory-link farm of every package
  # this process can see EXCEPT digest, so the very predicate the gate consults
  # -- requireNamespace("digest"), a base-internal hidden through
  # msuiter's own namespace chain -- answers FALSE on its own merits
  # (patching an imports-env binding was measured impossible: the binding
  # lives in the base namespace, which tests must not touch). The child
  # attests that probe -- a control that cannot say "digest was absent"
  # could ride the accelerator leg vacuously -- and must emit the digest
  # the in-process pure-R kernel computes. Both directions fire: digest
  # sneaking into the farm reddens the probe match; a broken fallback
  # reddens the bytes.
  ex <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(ex)) ex <- paste0(ex, ".exe")
  if (!file.exists(ex))
    stop("F2: Rscript not found -- the control cannot run", call. = FALSE)
  farm <- tempfile("cc-farm-")
  if (!dir.create(farm))
    stop("F2: the farm cannot be built", call. = FALSE)
  for (lib in unique(c(.libPaths(), .Library.site))) if (dir.exists(lib)) {
    for (pkg in list.files(lib, full.names = TRUE)) {
      nm <- basename(pkg)
      if (nm == "digest" || grepl("^[.]", nm)) next
      dst <- file.path(farm, nm)
      if (file.exists(dst)) next
      # Directory links: symlink where the platform permits it, and on
      # windows an mklink junction fallback (junctions need no elevated
      # privilege; windows symlinks do -- measured: silent link failure
      # leaves the farm holes and the child reddens on them).
      ok <- suppressWarnings(tryCatch({file.symlink(pkg, dst); TRUE},
                                      error = function(e) FALSE))
      if (!ok && identical(.Platform$os.type, "windows")) {
        st <- suppressWarnings(system2("cmd", c("/c", "mklink", "/J", dst, pkg),
                                       stdout = FALSE, stderr = FALSE))
        if (!identical(as.integer(st), 0L))
          stop("F2: neither symlink nor junction could link ", nm,
               " into the farm -- the control cannot run", call. = FALSE)
      }
    }
  }
  if (dir.exists(file.path(farm, "digest")))
    stop("F2: digest leaked into the farm -- the control cannot run",
         call. = FALSE)
  script <- tempfile("cc-absent-leg-.R")
  writeLines(c(
    "raw <- as.raw(0L:255L)",
    "suppressMessages(library(msuiter))",
    "# the probe runs INSIDE the msuiter namespace -- the gate's own",
    "# resolution chain, not the child's globalenv",
    "probe <- eval(substitute(requireNamespace(pkg, quietly = TRUE),",
    "                 list(pkg = 'digest')), envir = asNamespace('msuiter'))",
    "cat('probe=', isTRUE(probe), ' sha=', msuiter:::.ms_cc_sha256_raw(raw),",
    "    '\\n', sep = '')"), script)
  # The child's isolation is the R_LIBS_USER farm plus the R_LIBS_SITE/R_PROFILE/
  # R_ENIRON neutralizers, set around the spawn and restored after: every
  # platform drives the same Rscript invocation, no shell wrapper (measured:
  # /bin/sh is absent on windows and the spawn died at exit 127 there).
  # R_LIBS (the master variable) rides as well: under the covr coverage lane
  # the test parent carries covr's R_LIBS, which outranks the _USER/_SITE
  # pair and would hand the child the full library set -- digest included --
  # flipping the probe to TRUE (witnessed: PR #52 coverage run, shard 4).
  childenv <- c(R_LIBS = farm, R_LIBS_USER = farm, R_LIBS_SITE = "",
                R_PROFILE = "no", R_ENIRON = "no")
  prior <- Sys.getenv(names(childenv), unset = NA_character_)
  do.call(Sys.setenv, stats::setNames(as.list(childenv), names(childenv)))
  on.exit({
    for (i in seq_along(prior)) {
      nm <- names(prior)[i]
      if (is.na(prior[[i]])) Sys.unsetenv(nm)
      else do.call(Sys.setenv, stats::setNames(list(prior[[i]]), nm))
    }
  })
  of <- tempfile("cc-absent-out-"); ef <- paste0(of, ".err")
  st <- suppressWarnings(system2(ex, script, stdout = of, stderr = ef))
  expect_identical(as.integer(st), 0L,
                   info = paste0(readLines(ef, warn = FALSE), collapse = " | "))
  line <- paste0(readLines(of, warn = FALSE), collapse = "")
  expect_match(line, "^probe=FALSE sha=[0-9a-f]+$")
  expect_identical(sub("^probe=FALSE sha=", "", line),
                   msuiter:::.ms_fit_sha256(as.raw(0L:255L)))
})

test_that("the cache dir resolves option > env > user cache dir (F3)", {
  # Option wins over env; env wins over the default; the default is the
  # R-exported tools::R_user_dir(which = "cache") tree under the
  # catalog-currency leaf. Pre-landmine this last line called
  # tools::R_user_cache_dir -- an object the tools namespace does not
  # contain at all -- so the default leg reddened the pre-fix tree.
  withr::with_options(list(msuiter.catalog_currency.cache_dir = NULL), {
    withr::with_envvar(c(MSUITER_CATALOG_CURRENCY_CACHE_DIR = ""), {
      dflt <- msuiter:::.ms_cc_default_cache_dir()
      expect_identical(dflt,
                       file.path(tools::R_user_dir("msuiter", which = "cache"),
                                 "catalog-currency"))
      # Measured (2026-10-23): tools::R_user_dir computes the canonical
      # user-cache path but does not create it, and the accessor is a pure
      # precedence resolution by design -- directory creation is the
      # writer-side contract (.ms_cc_write_verbatim) -- asserted
      # right below so the two halves of the law both speak.
      created <- tempfile("cc-write-side-")
      wrote <- msuiter:::.ms_cc_write_verbatim(file.path(created, "frag"), "x")
      expect_true(dir.exists(dirname(wrote)))
    })
    withr::with_envvar(c(MSUITER_CATALOG_CURRENCY_CACHE_DIR = "/env-seed/cc"), {
      expect_identical(msuiter:::.ms_cc_default_cache_dir(), "/env-seed/cc")
    })
    withr::with_options(
      list(msuiter.catalog_currency.cache_dir = "/opt-seed/cc"),
      withr::with_envvar(c(MSUITER_CATALOG_CURRENCY_CACHE_DIR = "/env-seed/cc"), {
        expect_identical(msuiter:::.ms_cc_default_cache_dir(), "/opt-seed/cc")
      }))
  })
})
